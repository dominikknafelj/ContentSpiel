require "test_helper"

class Trash::EmptyTest < ActiveSupport::TestCase
  setup { Current.actor = users(:one) }

  test "empties pages, then posts, then images, skipping what can't go" do
    asset = create_media_asset
    stuck = create_media_asset
    page = create_page(title: "Hero page")
    assert Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id }).ok?
    keeper = create_page(title: "Keeper")
    assert Pages::Save.call(keeper, attributes: { hero_media_asset_id: stuck.id }).ok?
    post = create_post(title: "Bye")
    [ page, post ].each { |record| assert Trash::Move.call(record).ok? }
    assert Trash::Move.call(asset.reload).ok?
    stuck.update_columns(trashed_at: Time.current) # inconsistent: trashed yet used by a kept page

    service = Trash::Empty.new
    result = service.call

    assert result.ok?
    assert_equal 3, service.purged_count
    assert_equal [ stuck ], service.skipped.map { |skip| skip[:record] }
    assert_match(/Keeper/, service.skipped.first[:errors].first)
    assert Media::Asset.exists?(stuck.id)
    [ page, post, asset ].each { |record| assert_not record.class.exists?(record.id) }
    event = Audit::Event.find_by!(action: "trash.emptied")
    assert_equal({ "purged" => 3, "skipped" => 1 }, event.metadata)
  end

  # A page trashed on its own and then again with its parent is a trash root
  # of its own, yet goes with the parent's branch: it's counted once, when
  # it's actually tried, and never tried again once gone.
  test "a separately trashed subpage purged with its branch isn't tried twice" do
    parent = create_page(title: "Section")
    child = create_page(title: "Child", parent: parent)
    travel(-1.minute) { assert Trash::Move.call(parent).ok? }
    child.update_columns(trash_root_id: child.id, trashed_at: Time.current)

    service = Trash::Empty.new
    assert service.call.ok?

    assert_equal 1, service.purged_count
    assert_empty service.skipped
    assert_not Page.exists?(child.id)
    assert_equal 1, Audit::Event.where(action: "page.purged").count
  end

  test "needs trash.empty" do
    post = create_post(title: "Stays")
    assert Trash::Move.call(post).ok?

    result = Trash::Empty.call(actor: users(:reader))

    assert result.denied?
    assert Post.exists?(post.id)
    assert_not Audit::Event.exists?(action: "trash.emptied")
  end
end
