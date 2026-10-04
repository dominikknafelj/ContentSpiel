require "test_helper"
require "rake"

# `rich_text:migrate_from_action_text` (design spec §5) and the
# `RichText::ActionTextImport` it runs.
#
# The ActionText rows are injected through a small source object rather than
# built as real `action_text_rich_texts` rows: this task's own migration drops
# that table (and ActionText itself), so the test database no longer has
# it. The default source (`RichText::ActionTextImport::SqlSource`) reads the
# table with plain SQL for exactly that reason -- it has to keep loading
# once the gem's models are gone -- and its "the table is gone" branch is
# what the rake task test at the bottom exercises for real.
class RichTextMigrationTest < ActiveSupport::TestCase
  VIDEO_ID = "dQw4w9WgXcQ".freeze

  Source = Struct.new(:rows, :videos) do
    def available? = true
    def each_row(&) = rows.each(&)
    def youtube_video_id(id) = videos.to_h[id.to_s]
  end

  def row(record, body, locale: "en", name: "body")
    { "record_type" => record.class.name, "record_id" => record.id, "name" => name, "locale" => locale, "body" => body }
  end

  def youtube_sgid(id)
    SignedGlobalID.new(URI::GID.build(app: GlobalID.app, model_name: "YoutubeEmbed", model_id: id.to_s), for: "attachable").to_s
  end

  def run_import(rows, videos: {})
    out = StringIO.new
    RichText::ActionTextImport.new(source: Source.new(rows, videos), out: out).run
    out.string
  end

  setup do
    @post = create_post(title: "Hello")
    @block = root_page.content_blocks.create!(block_type: :rich_text, position: 0)
  end

  test "imports every row into its record's per-locale document and prints per-model counts" do
    output = run_import([
      row(@post, "<p>Hello <strong>world</strong></p>"),
      row(@post, "<p>Hallo Welt</p>", locale: "de"),
      row(@block, %(<p>Watch:</p><action-text-attachment sgid="#{youtube_sgid(1)}"></action-text-attachment>))
    ], videos: { "1" => VIDEO_ID })

    assert_equal rich_doc("Hello **world**"), @post.reload.body_document(locale: "en").to_h
    assert_equal rich_doc("Hallo Welt"), @post.body_document(locale: "de").to_h
    assert_equal %w[paragraph youtube], @block.reload.body_document(locale: "en").to_h["content"].map { |node| node["type"] }

    assert_match(/Post: 2 imported, 0 blank, 0 skipped, 0 failed/, output)
    assert_match(/ContentBlock: 1 imported, 0 blank, 0 skipped, 0 failed/, output)
  end

  test "an import leaves the stored translation state agreeing with Translations::Status" do
    with_locales(%w[en de], default: "en")
    Translations::StateIndex.rebuild_all
    run_import([ row(@post, "<p>Hallo Welt</p>", locale: "de"), row(@block, "<p>Hallo</p>", locale: "de") ])

    [ @post, root_page ].each do |owner|
      truth = Translations::Status.for([ owner.reload ])[owner].transform_values(&:to_s)
      stored = Translations::State.where(record_type: owner.class.polymorphic_name, record_id: owner.id).pluck(:locale, :state).to_h
      assert_equal truth, stored
    end
  end

  test "reports unmapped fragments with the record and locale they came from" do
    output = run_import([ row(@post, "<p>Keep <u>this</u></p>") ])

    assert_equal "Keep this", @post.reload.body_document(locale: "en").to_h.dig("content", 0, "content").sum("") { |node| node["text"] }
    assert_match(/Unmapped fragments \(1\)/, output)
    assert_match(%r{Post##{@post.id} \(en\):.*<u>}, output)
  end

  test "is idempotent and never overwrites a locale that already has a document" do
    @post.update!(body: rich_doc("Written in CS Studio"))

    output = run_import([ row(@post, "<p>Old ActionText body</p>"), row(@post, "<p>Deutsch</p>", locale: "de") ])
    assert_equal rich_doc("Written in CS Studio"), @post.reload.body_document(locale: "en").to_h
    assert_equal rich_doc("Deutsch"), @post.body_document(locale: "de").to_h
    assert_match(/Post: 1 imported, 0 blank, 1 skipped, 0 failed/, output)

    again = run_import([ row(@post, "<p>Old ActionText body</p>"), row(@post, "<p>Deutsch</p>", locale: "de") ])
    assert_match(/Post: 0 imported, 0 blank, 2 skipped, 0 failed/, again)
  end

  test "a failing row is recorded and the rest still import" do
    output = run_import([
      { "record_type" => "Post", "record_id" => 0, "name" => "body", "locale" => "en", "body" => "<p>orphan</p>" },
      { "record_type" => "Page", "record_id" => root_page.id, "name" => "body", "locale" => "en", "body" => "<p>pages have no body</p>" },
      row(@post, "<p>fine</p>", locale: "xx"),
      row(@post, "<p>fine</p>")
    ])

    assert_equal rich_doc("fine"), @post.reload.body_document(locale: "en").to_h
    assert_match(/Post: 1 imported, 0 blank, 0 skipped, 2 failed/, output)
    assert_match(/Page: 0 imported, 0 blank, 0 skipped, 1 failed/, output)
    assert_match(/Failures \(3\)/, output)
    assert_match(/Post#0 \(en\)/, output)
  end

  test "a blank ActionText body is skipped, not written" do
    output = run_import([ row(@post, "") ])

    assert_equal({}, @post.reload.read_attribute(:body))
    assert_match(/Post: 0 imported, 0 blank, 1 skipped, 0 failed/, output)
  end

  # Fix round 1 (m1/I1): a body with content whose conversion comes out
  # blank -- here, an attachment with no sgid (a remote file) -- is counted
  # and listed as blank, and nothing is written.
  test "a body that converts to a blank document is listed as blank, not written" do
    output = run_import([ row(@post, %(<action-text-attachment content-type="image/png" url="https://cdn.example/x.png"></action-text-attachment>)) ])

    assert_equal({}, @post.reload.read_attribute(:body))
    assert_match(/Post: 0 imported, 1 blank, 0 skipped, 0 failed/, output)
    assert_match(/Imported blank \(1\): check these, then migrate with FORCE_DROP_ACTION_TEXT=1\n  Post##{@post.id} \(en\)/, output)
  end

  # Fix round 1 (m3): a row that fails after its import already created a
  # `Media::Asset` rolls that asset back rather than orphaning it.
  test "a failing row leaves no Media::Asset behind" do
    blob = ActiveStorage::Blob.create_and_upload!(io: File.open(file_fixture("tiny.png")), filename: "tiny.png", content_type: "image/png")
    image = %(<action-text-attachment sgid="#{blob.to_sgid(for: "attachable")}" content-type="image/png"></action-text-attachment>)
    source = Source.new([ row(@post, image + %(<action-text-attachment sgid="#{youtube_sgid(1)}"></action-text-attachment>)) ], {})
    def source.youtube_video_id(_id) = raise("youtube_embeds is unreadable")

    out = StringIO.new
    assert_no_difference(-> { Media::Asset.count }) { RichText::ActionTextImport.new(source: source, out: out).run }

    assert_match(/Post: 0 imported, 0 blank, 0 skipped, 1 failed/, out.string)
    assert_match(/youtube_embeds is unreadable/, out.string)
  end

  # Final fix wave (C1): the import writes bodies past the services, so it
  # refreshes each written owner's usage rows itself -- an imported image
  # would otherwise read as "Unused" and could be deleted from under it.
  test "an imported image is indexed as a rich_text usage of its record and locale" do
    blob = ActiveStorage::Blob.create_and_upload!(io: File.open(file_fixture("tiny.png")), filename: "tiny.png", content_type: "image/png")
    image = %(<action-text-attachment sgid="#{blob.to_sgid(for: "attachable")}" content-type="image/png"></action-text-attachment>)

    run_import([ row(@post, image, locale: "de"), row(@block, image) ])

    asset = Media::Asset.joins(:file_blob).find_by!(active_storage_blobs: { id: blob.id })
    rows = Media::Usage.where(role: "rich_text").pluck(:media_asset_id, :owner_type, :owner_id, :locale)
    assert_equal [ [ asset.id, "ContentBlock", @block.id, "en" ], [ asset.id, "Post", @post.id, "de" ] ], rows.sort_by { |row| row[1] }
    assert_not_includes Media::Asset.unused, asset
  end

  test "the rake task says there is nothing to migrate once ActionText's table is gone" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("rich_text:migrate_from_action_text")
    task = Rake::Task["rich_text:migrate_from_action_text"]
    task.reenable

    assert_not ActiveRecord::Base.connection.table_exists?(:action_text_rich_texts)
    output, = capture_io { task.invoke }

    assert_match(/nothing to migrate/i, output)
  end
end
