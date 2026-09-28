require "test_helper"
require Rails.root.join("db/migrate/20260928040000_drop_action_text").to_s

# The safety net on `DropActionText#up` (design spec §5): it refuses to drop
# `action_text_rich_texts` while any ActionText body with visible content
# still has nothing to show for it in the record's JSON `body`, so running
# `db:migrate` before `rich_text:migrate_from_action_text` can't lose
# content. The test database no longer has ActionText's tables (this
# migration already ran against it), so each test recreates them inside its
# own transaction -- Postgres DDL is transactional, so they're rolled back
# with everything else.
class DropActionTextMigrationTest < ActiveSupport::TestCase
  def connection = ActiveRecord::Base.connection

  setup do
    connection.create_table :action_text_rich_texts do |t|
      t.string :name, null: false
      t.text :body
      t.references :record, null: false, polymorphic: true, index: false
      t.string :locale, null: false
      t.timestamps
    end
    connection.create_table(:youtube_embeds) { |t| t.string :video_id, null: false }

    @post = create_post(title: "Hello")
  end

  def insert_body(record, body, locale: "en")
    connection.execute(ActiveRecord::Base.sanitize_sql([
      "INSERT INTO action_text_rich_texts (name, body, record_type, record_id, locale, created_at, updated_at) VALUES ('body', ?, ?, ?, ?, now(), now())",
      body, record.class.name, record.id, locale
    ]))
  end

  def with_env(values)
    previous = values.keys.to_h { |key| [ key, ENV[key] ] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end

  def migrate_up = ActiveRecord::Migration.suppress_messages { DropActionText.new.migrate(:up) }

  test "refuses to drop ActionText while a body with content hasn't been imported" do
    insert_body(@post, "<p>Not imported yet</p>")

    error = assert_raises(StandardError) { migrate_up }

    assert_includes error.message, "run bin/rails rich_text:migrate_from_action_text first"
    assert connection.table_exists?(:action_text_rich_texts)
  end

  test "an attachment-only body counts as content too" do
    insert_body(@post, %(<action-text-attachment sgid="x"></action-text-attachment>))

    assert_raises(StandardError) { migrate_up }
  end

  # Fix round 1 (I1): a body whose only content can't be mapped imports as
  # blank, which the guard can't tell from "never converted" -- the task
  # lists it, and FORCE_DROP_ACTION_TEXT=1 is the way past the guard. Runs
  # the real task (and its SQL source) against the recreated table.
  test "an unmappable body blocks the drop until FORCE_DROP_ACTION_TEXT=1" do
    insert_body(@post, %(<action-text-attachment content-type="image/png" url="https://cdn.example/x.png"></action-text-attachment>))

    out = StringIO.new
    RichText::ActionTextImport.new(out: out).run
    assert_match(/Imported blank \(1\).*\n  Post##{@post.id} \(en\)/, out.string)

    error = assert_raises(StandardError) { migrate_up }
    assert_includes error.message, "FORCE_DROP_ACTION_TEXT=1"
    assert connection.table_exists?(:action_text_rich_texts)

    with_env("FORCE_DROP_ACTION_TEXT" => "1") { migrate_up }
    assert_not connection.table_exists?(:action_text_rich_texts)
  end

  test "drops ActionText once every body with content is imported" do
    @post.update!(body: rich_doc("Imported"))
    insert_body(@post, "<p>Imported</p>")
    # Nothing visible to lose: blank bodies, script-only bodies, rows whose
    # record is gone.
    other = create_post(title: "Other")
    insert_body(other, "<div><br></div>")
    insert_body(other, "<script>alert(1)</script>", locale: "de")
    connection.execute("INSERT INTO action_text_rich_texts (name, body, record_type, record_id, locale, created_at, updated_at) VALUES ('body', '<p>orphan</p>', 'Post', 0, 'en', now(), now())")

    migrate_up

    assert_not connection.table_exists?(:action_text_rich_texts)
    assert_not connection.table_exists?(:youtube_embeds)
  end
end
