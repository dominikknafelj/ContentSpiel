require "test_helper"

# `Admin::MediaLibrary::DetailComponent`'s trash-aware "Used on" panel (trash
# spec §4.1/§5.1, Task 4): a trashed owner is never named, and an asset used
# only by trashed owners says so instead of the ordinary "Not used anywhere
# yet". No trash service exists yet, so these tests set `trashed_at` directly
# the same way `test/models/media/usage_test.rb` does.
class Admin::MediaLibrary::DetailComponentTest < ViewComponent::TestCase
  include ContentHelper

  test "an asset used only by a trashed owner shows the trash-only message, not the usage list" do
    asset = create_media_asset
    page = create_page(title: "Hero page")
    Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id })
    page.update!(trashed_at: Time.current)

    render_inline Admin::MediaLibrary::DetailComponent.new(asset: asset.reload, locale: "en")

    assert_text "Used only by items in the trash."
    refute_text "Hero page"
    refute_text "Not used anywhere yet."
  end

  test "Used on lists a kept owner but not a trashed one for the same asset" do
    asset = create_media_asset
    kept_page = create_page(title: "Kept page")
    Pages::Save.call(kept_page, attributes: { hero_media_asset_id: asset.id })

    trashed_post = create_post(title: "Trashed post")
    Posts::Save.call(trashed_post, translations: { Locales.default => { body: rich_doc(%(::image{asset="#{asset.id}" alt="x"})) } })
    trashed_post.update!(trashed_at: Time.current)

    render_inline Admin::MediaLibrary::DetailComponent.new(asset: asset.reload, locale: "en")

    assert_text "Kept page"
    refute_text "Trashed post"
    refute_text "Used only by items in the trash."
  end

  test "an unused asset still shows Not used anywhere yet" do
    asset = create_media_asset

    render_inline Admin::MediaLibrary::DetailComponent.new(asset: asset, locale: "en")

    assert_text "Not used anywhere yet."
  end

  # Task 10: Move to trash is disabled only while a *kept* owner uses the
  # image -- an asset used solely by something already in the trash is the
  # same "trash_only" state as the first test above, and `Trash::Move`
  # itself would let this one through, so the button must too.
  test "Move to trash is enabled for an asset used only by a trashed owner" do
    asset = create_media_asset
    page = create_page(title: "Hero page")
    Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id })
    page.update!(trashed_at: Time.current)

    render_inline Admin::MediaLibrary::DetailComponent.new(asset: asset.reload, locale: "en")

    assert_selector "button", text: "Move to trash"
    assert_no_selector "button[disabled]", text: "Move to trash"
  end

  test "Move to trash is disabled, with the in-use reason, while a kept owner uses the image" do
    asset = create_media_asset
    page = create_page(title: "Hero page")
    Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id })

    render_inline Admin::MediaLibrary::DetailComponent.new(asset: asset.reload, locale: "en")

    assert_selector "button[disabled]", text: "Move to trash"
    assert_text asset.reload.in_use_message(kept_only: true)
  end
end
