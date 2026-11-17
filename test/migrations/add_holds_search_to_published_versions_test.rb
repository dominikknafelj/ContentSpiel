require "test_helper"
require Rails.root.join("db/migrate/20261117130000_add_holds_search_to_published_versions").to_s

# The migration marks every page copy, current, pending or older, whose
# blocks hold a Search block, as taking a copy now does
# (`Publishing::Snapshot.holds_search?`), and no other copy.
class AddHoldsSearchToPublishedVersionsMigrationTest < ActiveSupport::TestCase
  def mark = ActiveRecord::Migration.suppress_messages { AddHoldsSearchToPublishedVersions.new.mark_search_holders }

  def flags(record) = Publishing::Version.of(record).order(:number).pluck(:holds_search)

  test "the copies that hold a Search block are marked, whatever their age, and no other copy" do
    page = create_page(title: "Search")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "search" }).ok?
    publish_changes(page)
    assert ContentBlocks::Destroy.call(page.content_blocks.sole).ok?
    publish_changes(page)
    plain = create_page(title: "Plain")
    post = create_post(title: "A post")
    taken = flags(page)
    Publishing::Version.update_all(holds_search: false) # version: none (a test empties the column the migration fills)

    mark

    assert_equal taken, flags(page), "as taking the copies wrote it"
    assert_equal [ false, true, false ], flags(page)
    assert_equal [ false ], flags(plain)
    assert_equal [ false ], flags(post)
  end
end
