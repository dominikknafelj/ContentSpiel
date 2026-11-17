require "test_helper"

# The public render cache of rich text, read for a whole page at once
# (`RichText::RenderCache`): one batched read per page, a body read from a
# published copy named by the copy and the block instead of a walk of its
# document, and never a read or a write for a preview. On a real store, since
# the suite's null store would hide all of it.
class PublicRenderCacheTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @page = create_page(title: "Long page")
    %w[First Second Third].each { |words| add_block(:rich_text, rich_doc("#{words} words")) }
    add_block(:table, rich_doc("| Name | Value |\n| --- | --- |\n| one | 1 |", tables: true))
    add_block(:note, rich_doc("A note's words"))
    publish_changes(@page)
  end

  teardown { Rails.cache = @original_cache }

  def add_block(type, body)
    result = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: type.to_s },
      translations: { "en" => { body: body } })
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  def path = PublicSite::Urls.new.path_for(@page, "en")

  # Every cache event of rich text the block causes: `[event, keys, hits]`.
  def rich_text_cache_events
    events = []
    subscriber = lambda do |name, *, payload|
      keys = Array(payload[:key]).map(&:to_s).select { |key| key.start_with?("rich_text") }
      events << [ name.delete_suffix(".active_support"), keys, Array(payload[:hits]).map(&:to_s) ] if keys.any?
    end
    ActiveSupport::Notifications.subscribed(subscriber, /\Acache_\w+\.active_support\z/) { yield }
    events
  end

  def get_page
    get path
    assert_response :success
  end

  test "a page's blocks are read from the render cache in one batch, named by the copy and never by a digest" do
    get_page
    walked = 0
    digest = RichText::Document.instance_method(:digest)
    RichText::Document.define_method(:digest) { walked += 1; digest.bind_call(self) }
    events = begin
      rich_text_cache_events { get_page }
    ensure
      RichText::Document.define_method(:digest, digest)
    end

    reads = events.select { |name, *| name == "cache_read_multi" }
    assert_equal 1, reads.size, events.inspect
    keys, hits = reads.sole.drop(1)
    assert_equal 5, keys.size, "three texts, a table's cells and a note's body"
    assert_equal keys.sort, hits.sort, "all found"
    assert_equal 1, keys.count { |key| key.start_with?("rich_text_table_cells/") }
    copy = Publishing::Version.of(@page).order(:id).last.id
    keys.each { |key| assert_includes key, "/copy/#{copy}/", key }
    assert_equal [ "cache_read_multi" ], events.map(&:first), "no block reads or writes on its own"
    assert_equal 0, walked, "no document is walked for its key"
    assert_includes response.body, "Second words"
  end

  test "what the batch did not find is drawn and written once, and found by the next view" do
    first = rich_text_cache_events { get_page }
    assert_equal 1, first.count { |name, *| name == "cache_read_multi" }
    assert_equal 5, first.count { |name, *| name == "cache_write" }, first.inspect
    assert_empty first.select { |name, *| name == "cache_read" }, "a prefetched miss is not read again"

    assert_equal [ "cache_read_multi" ], rich_text_cache_events { get_page }.map(&:first)
  end

  test "a changed block, a new content version and a new code revision each draw again" do
    get_page
    block = @page.content_blocks.where(block_type: "rich_text").order(:position).second
    assert ContentBlocks::Save.call(block, attributes: {}, translations: { "en" => { body: rich_doc("Changed words") } }).ok?
    get_page
    assert_not_includes response.body, "Changed words", "a draft is not shown"

    publish_changes(@page)
    events = rich_text_cache_events { get_page }
    assert_includes response.body, "Changed words"
    assert_equal 5, events.count { |name, *| name == "cache_write" }, "a new copy and a new content version: every block misses"

    PublicSite.bump_version!
    Current.reset
    assert_equal 5, rich_text_cache_events { get_page }.count { |name, *| name == "cache_write" }, "a new content version"

    was = RichText.code_revision
    RichText.code_revision = "another-deploy"
    begin
      assert_equal 5, rich_text_cache_events { get_page }.count { |name, *| name == "cache_write" }, "a new code revision"
    ensure
      RichText.code_revision = was
    end
    assert_equal [ "cache_read_multi" ], rich_text_cache_events { get_page }.map(&:first), "and back on the old revision, all found"
  end

  test "a preview neither reads the render cache nor fills it" do
    sign_in_as(users(:one))
    events = rich_text_cache_events do
      get "/#{ContentSpiel::ADMIN_PATH}/preview#{path}"
      assert_response :success
    end
    assert_empty events
    assert_includes response.body, "Second words"
    assert_nil Current.rich_text_renders

    assert_equal 5, rich_text_cache_events { get_page }.count { |name, *| name == "cache_write" }, "the public page found nothing a preview left"
  end
end
