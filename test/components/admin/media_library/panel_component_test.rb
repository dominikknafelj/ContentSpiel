require "test_helper"

# `Admin::MediaLibrary::PanelComponent`'s trash-aware "Used on" panel (trash
# spec §4.1/§5.1, Task 4): a trashed owner is never listed as a place the image
# is used, and an asset used only by trashed owners says so (naming only the
# ones the viewer may read) instead of the ordinary "Not used anywhere yet".
# These tests set `trashed_at` directly the same way
# `test/models/media/usage_test.rb` does.
class Admin::MediaLibrary::PanelComponentTest < ViewComponent::TestCase
  include ContentHelper

  test "the trash-only message names only the trashed owners the viewer may read" do
    asset = create_media_asset
    page = create_page(title: "Secret page")
    Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id })
    page.update!(trashed_at: Time.current)
    viewer = media_only_viewer

    as(viewer) { render_inline Admin::MediaLibrary::PanelComponent.new(asset: asset.reload, locale: "en") }

    assert_text "Only by items in the trash."
    refute_text "Secret page"
  end

  test "view only: plain text, the B19 sentence, no form, no trash" do
    asset = create_media_asset
    assert Media::Save.call(asset, translations: { "en" => { alt: "Sand dunes" } }).ok?
    viewer = media_only_viewer

    as(viewer) { render_inline Admin::MediaLibrary::PanelComponent.new(asset: asset.reload, locale: "en") }

    assert_text "Only the uploader or a media manager can edit this image."
    assert_text "Sand dunes"
    assert_no_selector "form"
    assert_no_selector "input, textarea"
    assert_no_selector "button", text: /Move to trash/
  end

  test "the panel is a focusable region and its close link tells admin--media-panel which tile to return to" do
    asset = create_media_asset

    render_inline Admin::MediaLibrary::PanelComponent.new(asset: asset, locale: "en")

    assert_selector "section#media-panel[tabindex='-1'][data-admin--media-panel-target='panel']"
    assert_selector "a[aria-label='Close panel'][data-action='click->admin--media-panel#close'][data-admin--media-panel-tile-id-param='#{asset.id}']"
  end

  test "an editable panel carries the autosave form, the retention help and the warn hook while the alt is empty" do
    asset = create_media_asset

    render_inline Admin::MediaLibrary::PanelComponent.new(asset: asset, locale: "en")

    assert_selector "form[data-controller='admin--autosave'] input[name='media_asset[title]']"
    assert_selector ".admin-media-alt-warn input[name='media_asset[alt]'][placeholder='Add alt text']"
    assert_text "Kept in Trash for 30 days."
    assert_selector "button", text: "Move to trash…"
  end

  test "with an alt text the warn hook is gone" do
    asset = create_media_asset
    assert Media::Save.call(asset, translations: { "en" => { alt: "Sand dunes" } }).ok?

    render_inline Admin::MediaLibrary::PanelComponent.new(asset: asset.reload, locale: "en")

    assert_no_selector ".admin-media-alt-warn"
  end

  test "retention 0 says the trash is kept until someone empties it" do
    site_settings(:default).update!(trash_retention_days: 0)
    Current.reset

    render_inline Admin::MediaLibrary::PanelComponent.new(asset: create_media_asset, locale: "en")

    assert_text "Kept in Trash until someone empties it."
  end

  test "the panel keeps the grid's state in its links and its form's URL" do
    asset = create_media_asset

    render_inline Admin::MediaLibrary::PanelComponent.new(asset: asset, locale: "en", link_params: { q: "sun", filter: "unused", page: "2" })

    assert_selector "form[action='/cs-studio/media/#{asset.id}?filter=unused&page=2&q=sun']"
    assert_selector "a[aria-label='Close panel'][href='/cs-studio/media?filter=unused&page=2&q=sun']"
  end

  test "an asset used only by a trashed owner shows the trash-only message, not the usage list" do
    asset = create_media_asset
    page = create_page(title: "Hero page")
    Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id })
    page.update!(trashed_at: Time.current)

    render_inline Admin::MediaLibrary::PanelComponent.new(asset: asset.reload, locale: "en")

    assert_text "Only by items in the trash: “Hero page”."
    refute_text "Not used anywhere yet."
  end

  test "Used on lists a kept owner but not a trashed one for the same asset" do
    asset = create_media_asset
    kept_page = create_page(title: "Kept page")
    Pages::Save.call(kept_page, attributes: { hero_media_asset_id: asset.id })

    trashed_post = create_post(title: "Trashed post")
    Posts::Save.call(trashed_post, translations: { Locales.default => { body: rich_doc(%(::image{asset="#{asset.id}" alt="x"})) } })
    trashed_post.update!(trashed_at: Time.current)

    render_inline Admin::MediaLibrary::PanelComponent.new(asset: asset.reload, locale: "en")

    assert_text "Kept page"
    refute_text "Trashed post"
    refute_text "Only by items in the trash"
  end

  test "an unused asset still shows Not used anywhere yet" do
    asset = create_media_asset

    render_inline Admin::MediaLibrary::PanelComponent.new(asset: asset, locale: "en")

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

    render_inline Admin::MediaLibrary::PanelComponent.new(asset: asset.reload, locale: "en")

    assert_selector "button", text: "Move to trash…"
    assert_no_selector "button[disabled]", text: "Move to trash"
    # A whole-page answer, so the sidebar's Trash badge updates with it.
    assert_selector "dialog form[data-turbo-frame='_top'] input[name='_method'][value='delete']", visible: :all
  end

  test "Move to trash is disabled, with the in-use reason, while a kept owner uses the image" do
    asset = create_media_asset
    page = create_page(title: "Hero page")
    Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id })

    render_inline Admin::MediaLibrary::PanelComponent.new(asset: asset.reload, locale: "en")

    assert_selector "button[disabled]", text: "Move to trash"
    assert_text "Remove it there first."
  end

  test "an image in use explains why it can't be trashed and links to where it's used" do
    asset = create_media_asset
    page = create_page(title: "Hero page")
    Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id })

    render_inline Admin::MediaLibrary::PanelComponent.new(asset: asset.reload, locale: "en")

    assert_selector "button[disabled][aria-describedby='media-trash-help']", text: "Move to trash"
    assert_no_selector "button[disabled][title]", text: "Move to trash"
    assert_selector "#media-trash-help.text-dim", text: "In use on 1 page. Remove it there first."
    assert_selector "#media-trash-help a[href='#media-used-on']", text: "See where it's used"
    assert_selector "#media-used-on"
  end

  test "an image used in several places counts them" do
    asset = create_media_asset
    2.times { |i| Pages::Save.call(create_page(title: "Page #{i}"), attributes: { hero_media_asset_id: asset.id }) }

    render_inline Admin::MediaLibrary::PanelComponent.new(asset: asset.reload, locale: "en")

    assert_selector "#media-trash-help", text: "In use in 2 places. Remove it there first."
  end

  private

  def media_only_viewer
    group = AccessControl::Group.create!(name: "Media only #{SecureRandom.hex(4)}")
    group.grants.create!(permission: "media.upload")
    User.create!(email_address: "media-only-#{SecureRandom.hex(4)}@example.com", password: "password12345", password_confirmation: "password12345").tap do |viewer|
      AccessControl::Membership.create!(user: viewer, group: group)
    end
  end
end
