require "test_helper"

class Trash::MoveTest < ActiveSupport::TestCase
  setup { Current.actor = users(:one) }

  test "a page moves with its whole branch, which frees every URL" do
    parent = create_page(title: "Section")
    child = create_page(title: "Child", parent: parent)
    grandchild = create_page(title: "Grandchild", parent: child)
    [ parent, child, grandchild ].each { |page| assert PublicPath.where(record: page).exists? }

    result = Trash::Move.call(parent)

    assert result.ok?, result.errors.to_sentence
    assert_equal parent, result.record
    [ parent, child, grandchild ].each do |page|
      page.reload
      assert page.trashed?
      assert_equal users(:one), page.trashed_by
      assert_equal parent.id, page.trash_root_id
      assert_not PublicPath.where(record: page).exists?
    end
  end

  test "a descendant already in the trash keeps its own trash record" do
    parent = create_page(title: "Section")
    child = create_page(title: "Child", parent: parent)
    assert Trash::Move.call(child).ok?
    earlier = child.reload.trashed_at

    travel 1.minute do
      assert Trash::Move.call(parent).ok?
    end
    assert_equal child.id, child.reload.trash_root_id
    assert_equal earlier.to_i, child.trashed_at.to_i
  end

  test "the homepage can't be trashed" do
    result = Trash::Move.call(root_page)
    assert_not result.ok?
    assert_equal [ "The homepage can't be moved to the trash" ], result.errors
    assert_not root_page.reload.trashed?
  end

  test "a post moves and loses its URL; tags stay" do
    blog = create_page(title: "Blog")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: blog), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).ok?
    publish_changes(blog)
    post = create_post(title: "Hello", tags: [ "ruby" ])
    assert PublicPath.where(record: post).exists?
    assert Trash::Move.call(post).ok?
    assert post.reload.trashed?
    assert_equal users(:one), post.trashed_by
    assert_equal [ "ruby" ], post.tags.map(&:name)
    assert_not PublicPath.where(record: post).exists?
  end

  test "an image used by a kept owner is refused, one used only by trashed owners moves" do
    asset = create_media_asset
    page = create_page(title: "Hero page")
    assert Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id }).ok?

    refused = Trash::Move.call(asset)
    assert_not refused.ok?
    assert_equal [ "This image is used on the page “Hero page”" ], refused.errors
    assert_not asset.reload.trashed?

    assert Trash::Move.call(page).ok?
    assert Trash::Move.call(asset.reload).ok?
    assert asset.reload.trashed?
    assert_equal users(:one), asset.trashed_by
  end

  # The refusal names places for the service's own actor ("not found, not
  # forbidden"): a kept page the actor can't read isn't named by its title,
  # and only kept owners count (a trashed one isn't mentioned at all).
  test "an image refusal names a place the actor can't read neutrally, and skips trashed owners" do
    asset = create_media_asset
    secret = create_page(title: "Secret")
    assert Pages::Save.call(secret, attributes: { hero_media_asset_id: asset.id }).ok?
    binned = create_page(title: "Binned")
    assert Pages::Save.call(binned, attributes: { hero_media_asset_id: asset.id }).ok?
    assert Trash::Move.call(binned).ok?
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "media.manage", scope: {})

    refused = as(users(:editor_branch)) { Trash::Move.call(asset.reload) }

    assert_not refused.ok?
    assert_not refused.denied?
    assert_equal [ "This image is used on a page you can't open" ], refused.errors
    assert_not asset.reload.trashed?
  end

  test "posts a trashed listing page gave a URL lose it" do
    blog = create_page(title: "Blog")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: blog), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).ok?
    publish_changes(blog)
    post = create_post(title: "Hello")
    assert_not_nil PublicSite::Paths.current_path(post.reload, Locales.default)

    Trash::Move.call(blog)
    assert_nil PublicSite::Paths.current_path(post.reload, Locales.default)
  end

  test "records one trashed event per call, listing the pages that came along" do
    parent = create_page(title: "Section")
    child = create_page(title: "Child", parent: parent)
    assert_difference -> { Audit::Event.where(action: "page.trashed").count }, 1 do
      Trash::Move.call(parent)
    end
    event = Audit::Event.where(action: "page.trashed").last
    assert_equal [ "Page", parent.id ], [ event.subject_type, event.subject_id ]
    assert_equal [ child.id ], event.metadata["descendant_ids"]
    assert_equal [ "User", users(:one).id ], [ event.actor_type, event.actor_id ]
  end

  test "a post or an image records its own trashed event, with no descendants" do
    post = create_post(title: "Solo")
    Trash::Move.call(post)
    event = Audit::Event.where(action: "post.trashed").last
    assert_equal post.id, event.subject_id
    assert_equal({}, event.metadata)

    asset = create_media_asset
    Trash::Move.call(asset)
    assert_equal asset.id, Audit::Event.where(action: "media.trashed").last.subject_id
  end

  test "needs the item's delete right" do
    post = create_post(title: "Not yours")
    result = Trash::Move.call(post, actor: users(:reader))
    assert result.denied?
    assert_not post.reload.trashed?

    page = create_page(title: "Not yours either")
    assert Trash::Move.call(page, actor: users(:author)).denied?
    assert_not page.reload.trashed?
  end

  test "an image needs media.manage, or being its uploader" do
    asset = create_media_asset
    assert Trash::Move.call(asset, actor: users(:author)).denied?
    assert_not asset.reload.trashed?
  end

  test "an uploader may trash their own unused image with media.upload alone" do
    asset = create_media_asset
    asset.update_columns(created_by_id: users(:author).id)
    assert Trash::Move.call(asset, actor: users(:author)).ok?
    assert asset.reload.trashed?
    assert_equal users(:author), asset.trashed_by
  end

  test "trashing twice is refused" do
    post = create_post(title: "Once")
    Trash::Move.call(post)
    result = Trash::Move.call(post.reload)
    assert_not result.ok?
    assert_equal [ "It's already in the trash" ], result.errors
  end

  test "a root save that fails after the branch was flagged rolls the branch back too" do
    parent = create_page(title: "Section")
    child = create_page(title: "Child", parent: parent)
    # Raises only on the root, *after* `trash_descendants` has flagged the
    # child with `update_all`. Called inside an outer, joinable transaction
    # -- the way a caller such as `Trash::Empty` will -- since the test's
    # own fixture transaction isn't joinable and would hand the service a
    # savepoint whether it asked for one or not.
    parent.define_singleton_method(:save!) { |*| raise ActiveRecord::RecordInvalid, self }

    assert_no_difference -> { Audit::Event.where(action: "page.trashed").count } do
      result = Page.transaction { Trash::Move.call(parent) }
      assert_not result.ok?
    end
    assert_not parent.trashed?, "the in-memory record should read as kept again"
    assert_nil parent.trashed_by
    assert_not parent.reload.trashed?
    child.reload
    assert_not child.trashed?
    assert_nil child.trash_root_id
    assert PublicPath.where(record: child).exists?
  end

  # Setting the trash flags can't make a valid record invalid, so moving
  # one to the trash doesn't re-run its validations: a record that went
  # invalid under it (a removed plugin content type, a stricter schema, a
  # reserved slug after an ADMIN_PATH change) can still be cleared away,
  # the way the old permanent delete could.
  test "a record that fails today's validations can still be moved to the trash, then purged" do
    post = create_post(title: "Orphaned type")
    post.update_columns(content_type: "gone/plugin_type")
    assert_not post.reload.valid?

    result = Trash::Move.call(post)

    assert result.ok?, result.errors.to_sentence
    assert post.reload.trashed?
    assert_not PublicPath.where(record: post).exists?
    assert Trash::Purge.call(post).ok?
    assert_not Post.exists?(post.id)
  end

  test "moving a page leaves its kept siblings' positions alone" do
    first = create_page(title: "First")
    middle = create_page(title: "Middle")
    last = create_page(title: "Last")
    before = [ first, last ].map { |page| page.reload.position }

    assert Trash::Move.call(middle).ok?
    assert_equal before, [ first, last ].map { |page| page.reload.position }
  end
end
