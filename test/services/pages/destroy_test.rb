require "test_helper"

class Pages::DestroyTest < ActiveSupport::TestCase
  test "refuses the root and pages with children, deletes leaves" do
    parent = create_page(title: "Parent")
    leaf = create_page(title: "Leaf", parent: parent)

    assert_not Pages::Destroy.call(root_page, actor: nil).ok?
    result = Pages::Destroy.call(parent, actor: nil)
    assert_not result.ok?
    assert_includes result.errors, "cannot delete a page that still has children"

    assert Pages::Destroy.call(leaf, actor: nil).ok?
    assert_not Page.exists?(leaf.id)
  end

  # Media library design spec §5.1: a destroyed page leaves no usage rows,
  # neither its own hero's nor its blocks' (destroyed along with it).
  test "deleting a page removes its own and its blocks' usages" do
    asset = create_media_asset
    page = create_page(title: "Leaf")
    Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id })
    block = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "image", media_asset_id: asset.id }).record
    assert_equal 2, asset.usages.count

    assert Pages::Destroy.call(page, actor: nil).ok?

    assert_not ContentBlock.exists?(block.id)
    assert_equal 0, asset.usages.count
  end
end
