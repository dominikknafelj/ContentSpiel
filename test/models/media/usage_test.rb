require "test_helper"

# `Media::Usage.by_kept_owner`/`Media::Asset#used_by_kept_owner?`/`#usage_state`
# (trash spec §4.1/§5.1): telling a kept reference apart from one that's
# only still there because its owner hasn't been purged yet. No trash
# service exists yet (Task 4), so these tests set `trashed_at` directly --
# `update!` on a Page/Post still runs the ordinary URL callbacks.
class Media::UsageTest < ActiveSupport::TestCase
  include ContentHelper

  test "usage_state tells kept use, trash-only use and no use apart" do
    asset = create_media_asset
    assert_equal :unused, asset.usage_state

    page = create_page(title: "Hero page")
    Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id })
    assert_equal :in_use, asset.reload.usage_state

    page.update!(trashed_at: Time.current)
    assert_equal :trash_only, asset.reload.usage_state
    assert asset.used?
    assert_not asset.used_by_kept_owner?
  end

  test "a block's usage counts as kept only while the block's page or post is kept" do
    asset = create_media_asset
    post = create_post(title: "Pictures")
    block = ContentBlock.create!(owner: post, block_type: "image", position: 1, media_asset: asset)
    Media::UsageIndex.refresh(block)
    assert asset.used_by_kept_owner?

    post.update!(trashed_at: Time.current)
    assert_not asset.reload.used_by_kept_owner?
  end

  # `Media::Asset.unused` stays a plain "no usage row at all" check (Task 4
  # controller ruling): an image used only by a trashed owner still has a
  # `media_usages` row, so it's correctly not "unused" -- trashing its owner
  # doesn't quietly move it into the Unused filter, which would invite
  # deleting an image a restore could still need.
  test "an image used only by a trashed owner is not unused" do
    asset = create_media_asset
    page = create_page(title: "Hero page")
    Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id })
    page.update!(trashed_at: Time.current)

    assert_not_includes Media::Asset.unused, asset
    assert asset.used?
  end
end
