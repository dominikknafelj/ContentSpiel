require "test_helper"

# Final fix wave I3: editing a block is editing its owner, so every block
# write bumps the owner's `updated_at` (the dashboard's "edited 2h ago" line
# orders by it) -- through `touch`, which runs no save callbacks, so the
# page's own path/hierarchy rebuild (`Page#sync_public_paths`, closure_tree's
# `after_save`) never runs for a block edit.
#
# The page is live: the touch is also what moves the public content version
# for a block edit (`Publishable#bump_public_version_when_live`), and that
# version moves only for published output. A draft's block edit touches its
# page all the same and moves no version (the last test).
class ContentBlocks::OwnerTouchTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Owner")
    @block = ContentBlocks::Save.call(@page.content_blocks.new, attributes: { block_type: "rich_text" }).record
    travel 1.minute
  end

  test "saving a block touches its page without rebuilding the page's paths" do
    before = @page.reload.updated_at
    version = PublicSite.content_version
    sql = capture_sql do
      assert ContentBlocks::Save.call(@block, translations: { Locales.default => { body: rich_doc("Edited") } }).ok?
    end

    assert_operator @page.reload.updated_at, :>, before
    assert_not_equal version, PublicSite.content_version
    assert_empty sql.grep(/public_paths|page_hierarchies/i), "a block edit rebuilt the page's paths:\n#{sql.join("\n")}"
  end

  test "creating, reordering and deleting blocks touch the page" do
    before = @page.reload.updated_at
    other = ContentBlocks::Save.call(@page.content_blocks.new, attributes: { block_type: "rich_text" }).record
    assert_operator (after_create = @page.reload.updated_at), :>, before

    travel 1.minute
    assert ContentBlocks::Reorder.call(@page, [ other.id, @block.id ]).ok?
    assert_operator (after_reorder = @page.reload.updated_at), :>, after_create

    travel 1.minute
    assert ContentBlocks::Destroy.call(other).ok?
    assert_operator @page.reload.updated_at, :>, after_reorder
  end

  test "a refused block edit doesn't touch the page" do
    before = @page.reload.updated_at
    result = ContentBlocks::Save.call(@block, translations: { Locales.default => { body: rich_doc("No") } }, actor: users(:reader))

    assert result.denied?
    assert_equal before, @page.reload.updated_at
  end

  test "a draft page's block edit touches the page and leaves the public content version alone" do
    page = create_page(title: "Draft owner", published: false)
    block = ContentBlocks::Save.call(page.content_blocks.new, attributes: { block_type: "rich_text" }).record
    travel 1.minute
    before = page.reload.updated_at
    version = PublicSite.content_version

    assert ContentBlocks::Save.call(block, translations: { Locales.default => { body: rich_doc("Edited") } }).ok?

    assert_operator page.reload.updated_at, :>, before
    assert_equal version, PublicSite.content_version
  end

  private

  def capture_sql
    statements = []
    callback = ->(*, payload) { statements << payload[:sql] unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    statements
  end
end
