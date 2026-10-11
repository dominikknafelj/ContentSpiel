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

  test "the panel is a focusable region and its close link tells admin--media--panel which tile to return to" do
    asset = create_media_asset

    render_inline Admin::MediaLibrary::PanelComponent.new(asset: asset, locale: "en")

    assert_selector "section#media-panel[tabindex='-1'][data-admin--media--panel-target='panel']"
    assert_selector "a[aria-label='Close panel'][data-action='click->admin--media--panel#close'][data-admin--media--panel-tile-id-param='#{asset.id}']"
  end

  test "an editable panel carries the autosave form, the retention help and the warn hook while the alt is empty" do
    asset = create_media_asset

    render_inline Admin::MediaLibrary::PanelComponent.new(asset: asset, locale: "en")

    assert_selector "form[data-controller='admin--saving--autosave'] input[name='media_asset[title]']"
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

  class HeaderProbeComponent < ViewComponent::Base
    def initialize(**) = nil

    def call = tag.b("header", data: { slot_probe: "header" })
  end

  class SectionsProbeComponent < ViewComponent::Base
    def initialize(**) = nil

    def call = tag.b("sections", data: { slot_probe: "sections" })
  end

  test "the panel's slots stand at the right end of the file-name row and below Used on, and draw nothing while empty" do
    asset = create_media_asset

    Admin::Slots.with("media.panel.header" => [ HeaderProbeComponent ], "media.panel.sections" => [ SectionsProbeComponent ]) do
      render_inline Admin::MediaLibrary::PanelComponent.new(asset: asset.reload, locale: "en")
    end

    html = rendered_content
    order = [ "media-panel-title", 'data-slot-probe="header"', "<img", "Used on", 'data-slot-probe="sections"', "Move to trash" ].map { |needle| html.index(needle) }
    assert_not_includes order, nil
    assert_equal order.sort, order
  end

  # Presence handoff 13: the people stand between the file name and the "×".
  # The name takes the room that is left and is cut on ONE line (the whole
  # name is its `title`, and is in full in the fields below); what the slot
  # draws never gives way; the "×" stays last.
  test "the file-name row: the name is cut on one line with the whole name as its title, the slot follows 8px after it and the close 12px after that" do
    asset = create_media_asset
    asset.update_columns(title: "a-very-long-file-name-that-would-have-wrapped-over-three-lines.png") # version: none (a component test's own image)

    Admin::Slots.with("media.panel.header" => [ HeaderProbeComponent ], "media.panel.sections" => []) do
      render_inline Admin::MediaLibrary::PanelComponent.new(asset: asset.reload, locale: "en")
    end

    row = page.find("#media-panel > div:first-child")
    assert_equal %w[flex gap-2 items-start], row[:class].split.sort
    assert_equal [ "h2", "b", "a" ], row.all(:xpath, "./*").map(&:tag_name)
    heading = row.find("h2#media-panel-title")
    assert_equal %w[flex-1 font-semibold min-w-0 text-ink text-lg truncate], heading[:class].split.sort
    assert_selector "h2#media-panel-title > span[title='#{asset.title}']", text: asset.title, exact_text: true
    close = row.find("a[aria-label='Close panel']")
    assert_includes close[:class].split, "ml-1"
    assert_includes close[:class].split, "shrink-0"
  end

  test "with nobody else on the image the row is the name and the close, and presence's element is there without a group" do
    asset = create_media_asset

    as(users(:one)) { render_inline Admin::MediaLibrary::PanelComponent.new(asset: asset.reload, locale: "en") }

    row = page.find("#media-panel > div:first-child")
    assert_equal [ "h2", "div", "a" ], row.all(:xpath, "./*", visible: :all).map(&:tag_name)
    row.assert_selector "div.hidden.flex-none.ml-auto[data-controller='admin--presence--record'] turbo-frame#presence-media-#{asset.id}", visible: :all
    row.assert_no_selector "button", visible: :all
  end

  test "with nothing registered at its slots the panel is the panel without the notes section" do
    Admin::Slots.with("media.panel.header" => [], "media.panel.sections" => []) do
      render_inline Admin::MediaLibrary::PanelComponent.new(asset: create_media_asset, locale: "en")
    end

    assert_selector "#media-panel"
    assert_no_selector "#media-notes"
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
