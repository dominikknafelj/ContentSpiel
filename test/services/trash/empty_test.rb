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
    # One event per page, the child's recorded by its parent's branch
    # purge -- not a second one from trying the child again.
    assert_equal [ child.id, parent.id ].sort, Audit::Event.where(action: "page.purged").pluck(:subject_id).sort
  end

  # Trash spec §4.4, "a failing item doesn't stop the run": an exception
  # out of one purge (a callback raising, a lost connection to storage)
  # is reported as a skip, the rest still go, and the run is still
  # summarised.
  test "an item whose purge raises is skipped, and the rest still go" do
    broken = create_post(title: "Broken")
    fine = create_post(title: "Fine")
    [ broken, fine ].each { |record| assert Trash::Move.call(record).ok? }
    original = Trash::Purge.method(:call)

    service = Trash::Empty.new
    result = with_singleton_override(Trash::Purge, :call, ->(record, **options) {
      raise ArgumentError, "boom" if record.id == broken.id
      original.call(record, **options)
    }) { service.call }

    assert result.ok?
    assert_equal 1, service.purged_count
    assert_equal [ broken ], service.skipped.map { |skip| skip[:record] }
    assert_equal [ "Couldn't be deleted: ArgumentError" ], service.skipped.first[:errors]
    assert Post.exists?(broken.id)
    assert_not Post.exists?(fine.id)
    event = Audit::Event.find_by!(action: "trash.emptied")
    assert_equal({ "purged" => 1, "skipped" => 1 }, event.metadata)
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
