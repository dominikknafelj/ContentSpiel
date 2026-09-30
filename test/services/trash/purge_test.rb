require "test_helper"

# `Trash::Purge` (trash spec §4.3): the permanent delete, reachable only
# from the trash. Absorbs what `Pages::Destroy`'s and `Media::Destroy`'s own
# tests covered -- usages cleaned up with their owners, an image refused
# while anything (a trashed owner included) still uses it, the foreign key
# backing that up when the usage index is behind.
class Trash::PurgeTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup { Current.actor = users(:one) }

  def upload_by(user)
    file = Rack::Test::UploadedFile.new(file_fixture("tiny.png"), "image/png")
    result = Media::Upload.call(file: file, actor: user)
    assert result.ok?, result.errors.inspect
    result.record
  end

  test "a page branch goes for good, deepest first, with blocks and usages" do
    asset = create_media_asset
    parent = create_page(title: "Section")
    child = create_page(title: "Child", parent: parent)
    block = ContentBlock.create!(owner: child, block_type: "image", position: 1, media_asset: asset)
    Media::UsageIndex.refresh(block)
    assert asset.used?
    assert Trash::Move.call(parent).ok?

    result = Trash::Purge.call(parent.reload)

    assert result.ok?, result.errors.to_sentence
    assert_not Page.exists?(parent.id)
    assert_not Page.exists?(child.id)
    assert_not ContentBlock.exists?(block.id)
    assert_not Media::Usage.exists?(media_asset_id: asset.id)
    assert Audit::Event.where(action: "page.purged", subject_id: parent.id).exists?
  end

  # Carried over from `Pages::Destroy`: the page's own hero row goes too,
  # not only its blocks'.
  test "a page's own hero usage goes with it" do
    asset = create_media_asset
    page = create_page(title: "Leaf")
    assert Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id }).ok?
    assert ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "image", media_asset_id: asset.id }).ok?
    assert_equal 2, asset.usages.count
    assert Trash::Move.call(page).ok?

    assert Trash::Purge.call(page.reload).ok?
    assert_equal 0, asset.usages.count
  end

  test "a separately trashed descendant goes with the branch" do
    parent = create_page(title: "Section")
    child = create_page(title: "Child", parent: parent)
    assert Trash::Move.call(child).ok?
    assert Trash::Move.call(parent.reload).ok?

    assert Trash::Purge.call(parent.reload).ok?
    assert_not Page.exists?(child.id)
  end

  test "a branch with a kept page under it is refused, and nothing goes" do
    parent = create_page(title: "Section")
    child = create_page(title: "Child", parent: parent)
    assert Trash::Move.call(parent).ok?
    child.update_columns(trashed_at: nil, trash_root_id: nil)

    result = Trash::Purge.call(parent.reload)

    assert_not result.ok?
    assert_equal [ "A page under it isn't in the trash" ], result.errors
    assert Page.exists?(parent.id)
    assert Page.exists?(child.id)
    assert_not Audit::Event.exists?(action: "page.purged")
  end

  # Purging a subpage out of a branch still in the trash would leave that
  # branch's later restore incomplete: it's the branch root that goes.
  test "a page trashed as part of another page's branch is refused, naming the root" do
    parent = create_page(title: "Section")
    child = create_page(title: "Child", parent: parent)
    assert Trash::Move.call(parent).ok?

    result = Trash::Purge.call(child.reload)

    assert_not result.ok?
    assert_not result.denied?
    assert_equal [ "Delete “Section” permanently to remove this page" ], result.errors
    assert Page.exists?(child.id)
    assert_not Audit::Event.exists?(action: "page.purged")
  end

  # Once the root is gone (or back out of the trash), a leftover member is
  # no longer part of anyone's pending restore.
  test "a branch member whose root isn't in the trash any more can go" do
    parent = create_page(title: "Section")
    child = create_page(title: "Child", parent: parent)
    assert Trash::Move.call(parent).ok?
    parent.update_columns(trashed_at: nil, trash_root_id: nil)

    assert Trash::Purge.call(child.reload).ok?
    assert_not Page.exists?(child.id)
  end

  test "a kept record can't be purged" do
    post = create_post(title: "Here")

    result = Trash::Purge.call(post)

    assert_not result.ok?
    assert_not result.denied?
    assert_equal [ "Only items in the trash can be deleted permanently" ], result.errors
    assert Post.exists?(post.id)
  end

  test "a post goes with its tags' join rows and records post.purged" do
    post = create_post(title: "Bye", tags: [ "ruby" ])
    assert Trash::Move.call(post).ok?

    assert Trash::Purge.call(post.reload).ok?
    assert_not Post.exists?(post.id)
    assert_not PostTag.exists?(post_id: post.id)
    assert_equal "Bye", Audit::Event.find_by!(action: "post.purged").snapshot.dig("title", "en")
  end

  test "posts.delete is needed for a post" do
    post = create_post(title: "Guarded")
    assert Trash::Move.call(post).ok?

    result = as(users(:reader)) { Trash::Purge.call(post.reload) }

    assert result.denied?
    assert Post.exists?(post.id)
    assert Audit::Event.exists?(action: "access.denied")
  end

  test "an image used by a trashed page can't be purged until that page is" do
    asset = create_media_asset
    page = create_page(title: "Hero page")
    assert Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id }).ok?
    assert Trash::Move.call(page).ok?
    assert Trash::Move.call(asset.reload).ok?

    refused = Trash::Purge.call(asset.reload)
    assert_not refused.ok?
    assert_match(/\AThis image is used on /, refused.errors.first)
    assert Trash::Purge.call(page.reload).ok?
    assert Trash::Purge.call(asset.reload).ok?
    assert_not Media::Asset.exists?(asset.id)
  end

  # Carried over from `Media::DestroyTest`: `Media::Asset#in_use_message`
  # names three places, counts the rest, and names a block's usage by the
  # page or post it sits on -- here every owner is itself in the trash.
  test "the refusal lists three usages and counts the rest, blocks named by their page or post" do
    asset = upload_by(users(:author))
    owners = %w[One Two Three].map do |title|
      page = create_page(title: title)
      assert Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id }).ok?
      page
    end
    four = create_page(title: "Four")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: four), attributes: { block_type: "image", media_asset_id: asset.id }).ok?
    five = create_post(title: "Five")
    assert Posts::Save.call(five, translations: { "en" => { body: rich_doc("::image{asset=\"#{asset.id}\"}") } }).ok?
    [ *owners, four, five ].each { |owner| assert Trash::Move.call(owner).ok? }
    assert Trash::Move.call(asset.reload).ok?

    result = as(users(:two)) { Trash::Purge.call(asset.reload) }

    assert_not result.ok?
    assert_equal [ "This image is used on the page “One”, the page “Two”, the page “Three” and 2 more" ], result.errors
  end

  # "Not found, not forbidden": a place the acting user can't read is named
  # neutrally, never by its title.
  test "a place the actor can't read is named neutrally" do
    asset = upload_by(users(:author))
    page = create_page(title: "Secret")
    assert Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id }).ok?
    assert Trash::Move.call(page).ok?
    assert Trash::Move.call(asset.reload).ok?
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "media.manage", scope: {})

    result = as(users(:editor_branch)) { Trash::Purge.call(asset.reload) }

    assert_not result.ok?
    assert_not result.denied?
    assert_equal [ "This image is used on a page you can't open" ], result.errors
  end

  test "an unused image goes, records media.purged and purges the file after commit" do
    asset = upload_by(users(:author))
    blob = asset.file.blob
    assert as(users(:two)) { Trash::Move.call(asset) }.ok?

    result = nil
    assert_difference "Media::Asset.count", -1 do
      result = as(users(:two)) { Trash::Purge.call(asset.reload) }
    end

    assert result.ok?, result.errors.inspect
    event = Audit::Event.find_by!(action: "media.purged")
    assert_equal "tiny", event.subject_label
    assert_equal "tiny.png", event.snapshot["filename"]
    assert_enqueued_with(job: ActiveStorage::PurgeJob, args: [ blob ])
  end

  test "the uploader purges their own upload without media.manage" do
    asset = upload_by(users(:author))
    assert as(users(:author)) { Trash::Move.call(asset) }.ok?

    assert as(users(:author)) { Trash::Purge.call(asset.reload) }.ok?
    assert_not Media::Asset.exists?(asset.id)
  end

  test "someone else without media.manage is denied" do
    asset = upload_by(users(:one))
    assert Trash::Move.call(asset).ok?

    result = as(users(:author)) { Trash::Purge.call(asset.reload) }

    assert result.denied?
    assert_equal [ "You don't have permission to manage media" ], result.errors
    assert Media::Asset.exists?(asset.id)
    assert_not Audit::Event.exists?(action: "media.purged")
  end

  # Review Focus 4 of the media library: the usage index is behind (a race,
  # a raw write) -- the service's own check passes, the FK still restricts,
  # and the database error becomes a failure rather than a 500.
  test "an unindexed reference is caught by the foreign key and fails cleanly" do
    asset = upload_by(users(:author))
    assert Trash::Move.call(asset).ok?
    page = create_page(title: "Raced")
    page.update_column(:hero_media_asset_id, asset.id)
    assert_not asset.used?

    result = Trash::Purge.call(asset.reload)

    assert_not result.ok?
    assert_equal [ "This image is still in use and can't be deleted" ], result.errors
    assert Media::Asset.exists?(asset.id)
    assert asset.reload.file.attached?
    assert_not Audit::Event.exists?(action: "media.purged")
    assert_no_enqueued_jobs(only: ActiveStorage::PurgeJob)
  end

  # A destroy halted by a callback without adding an error (`throw :abort`)
  # still answers with a message about deleting -- not the generic "could
  # not be saved".
  test "a destroy halted without errors fails with a deletion message" do
    asset = upload_by(users(:author))
    assert Trash::Move.call(asset).ok?
    asset.reload

    result = with_singleton_override(asset, :destroy, -> { false }) { Trash::Purge.call(asset) }

    assert_not result.ok?
    assert_equal [ "This image couldn't be deleted" ], result.errors
    assert Media::Asset.exists?(asset.id)
    assert_not Audit::Event.exists?(action: "media.purged")
  end

  test "trash.empty allows purging any single item without the item's own delete right" do
    emptier = User.create!(email_address: "emptier@example.com", password: "a-long-enough-password")
    group = AccessControl::Group.create!(name: "Trash emptiers")
    AccessControl::Grant.create!(group: group, permission: "trash.empty", scope: {})
    AccessControl::Membership.create!(user: emptier, group: group)
    trashed = create_post(title: "Gone")
    assert Trash::Move.call(trashed).ok?
    kept = create_post(title: "Staying")

    purged = as(emptier) { Trash::Purge.call(trashed.reload) }
    assert purged.ok?, purged.errors.to_sentence
    assert_not Post.exists?(trashed.id)

    moved = as(emptier) { Trash::Move.call(kept) }
    assert moved.denied?
    assert_not kept.reload.trashed?
  end
end
