require "test_helper"

# `Admin::MediaLibrary::PanelComponent`, the Media rail's Image tab: its
# parts in order, the view-only reader's facts, and the trash-aware "Used on":
# a trashed owner is never listed as a place the image is used, and an asset
# used only by trashed owners says so (naming only the ones the viewer may
# read) instead of the ordinary "Not used anywhere yet". These tests set
# `trashed_at` directly the same way `test/models/media/usage_test.rb` does.
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

  test "view only: plain text, the sentence naming who may edit, no form, no trash" do
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

  # Anyone the panel is drawn for may open it (`media.upload`), editor or
  # not, so the link is there for a viewer who cannot edit the image too. It
  # is a plain download, never a Turbo visit, and never an Active Storage URL.
  test "the panel offers Download original to someone who may open it" do
    asset = create_media_asset

    as(media_only_viewer) { render_inline Admin::MediaLibrary::PanelComponent.new(asset: asset, locale: "en") }

    assert_selector "a[href='/cs-studio/media/#{asset.id}/original'][data-turbo='false'][download]", text: "Download original"
    assert_no_selector "a[href*='/rails/active_storage']"
    assert_selector "p.text-sm.text-meta", text: "Only editors can download the original."
  end

  test "the panel draws no close of its own; the rail does" do
    asset = create_media_asset

    render_inline Admin::MediaLibrary::PanelComponent.new(asset: asset, locale: "en")

    assert_selector "section#media-panel[tabindex='-1'][data-admin--media--panel-target='panel']"
    assert_no_selector "a[aria-label='Close panel'], [data-action*='admin--media--panel#close']", wait: 0
    assert_not_respond_to Admin::MediaLibrary::PanelComponent.new(asset: asset, locale: "en"), :close_path
  end

  test "the Image tab: the title in text-h2, a borderless preview, the facts, Download original, the tabs, the wells, Used on with each record's chip, the sections slot, then the trash after a rule" do
    asset = create_media_asset
    kept_page = create_page(title: "Kept page")
    Pages::Save.call(kept_page, attributes: { hero_media_asset_id: asset.id })
    post = create_post(title: "A post")
    Posts::Save.call(post, translations: { Locales.default => { body: rich_doc(%(::image{asset="#{asset.id}" alt="x"})) } })
    asset.reload

    Admin::Slots.with("media.panel.header" => [], "media.panel.sections" => [ SectionsProbeComponent ]) do
      as(users(:one)) { render_inline Admin::MediaLibrary::PanelComponent.new(asset: asset, locale: "en") }
    end

    assert_selector "#media-panel > div:first-child h2#media-panel-title.text-h2.text-ink"
    preview = page.find("#media-panel > span:has(img, [data-image-empty])")
    assert_equal %w[bg-sunken block overflow-hidden rounded-tile], preview[:class].split.sort
    assert_selector "#media-panel dl dt", text: "Type"
    page.all("#media-panel dl.text-label > dd").each { |value| assert_includes value[:class].split, "text-ink" }
    download = page.find("#media-panel a[download]", text: "Download original")
    assert_equal Admin::Ui::ButtonComponent.classes(:tertiary, size: :small).split.sort, (download[:class].split - %w[self-start]).sort
    assert_selector "#media-panel h3#media-used-on.text-h3.text-ink", text: "Used on"
    { "page" => "Kept page", "post" => "A post" }.each do |kind, title|
      row = page.find("#media-panel li[data-used-on='#{kind}']")
      assert_equal %w[span a], row.all(:xpath, "./*").map(&:tag_name)
      assert_equal "true", row.find(:xpath, "./span")["aria-hidden"], "the chip is hidden from a screen reader: the row's words name the kind"
      assert_selector "#media-panel li[data-used-on='#{kind}'] > a", text: title
    end
    trash = page.find("#media-panel > section.admin-action-zone:last-child")
    assert_equal %w[border-line border-t], trash[:class].split.grep(/\Aborder/).sort

    html = rendered_content
    order = [ "media-panel-title", "<img", "Download original", "admin-language-tabs", "media_asset[title]", "media_asset[alt]", "media_asset[caption]",
              "Used on", 'data-slot-probe="sections"', "Move to trash" ].map { |needle| html.index(needle) }
    assert_not_includes order, nil
    assert_equal order.sort, order
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
    assert_selector ".admin-language-tabs a[href*='filter=unused'][href*='page=2'][href*='q=sun']", minimum: 1
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

  # Move to trash is disabled only while a *kept* owner uses the
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

  # The shared zone with no heading: named by the trigger's words, the cost
  # line first in `text-small text-dim`, the trigger under it, and the
  # confirm dialog after the zone, outside it.
  test "Move to trash is the shared action zone with no heading, in use and not" do
    asset = create_media_asset
    render_inline Admin::MediaLibrary::PanelComponent.new(asset: asset, locale: "en")

    assert_selector "section.admin-action-zone[aria-label='Move to trash'][data-zone=trash] > div > p#media-trash-help.text-small.text-dim"
    assert_selector "section[data-zone=trash] > button[aria-describedby='media-trash-help']", text: "Move to trash…"
    assert_no_selector "section[data-zone=trash] h2, section[data-zone=trash] h3"
    assert_no_selector "section[data-zone=trash] dialog", visible: :all
    assert_selector "section[data-zone=trash] + dialog", visible: :all

    Pages::Save.call(create_page(title: "Hero page"), attributes: { hero_media_asset_id: asset.id })
    render_inline Admin::MediaLibrary::PanelComponent.new(asset: asset.reload, locale: "en")

    assert_selector "section[data-zone=trash] > div > p#media-trash-help.text-small.text-dim a[href='#media-used-on']", text: "See where it's used"
    assert_selector "section[data-zone=trash] > button[disabled][aria-describedby='media-trash-help']", text: "Move to trash…"
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

  # The people stand after the title. The name takes the room that is left
  # and is cut on ONE line (the whole name is its `title`, and is in full in
  # the fields below); what the slot draws never gives way; the row keeps
  # clear of the rail's Close, which stands over its right end.
  test "the title row: the name is cut on one line with the whole name as its title, the slot follows 8px after it, and the row keeps room for the rail's close" do
    asset = create_media_asset
    asset.update_columns(title: "a-very-long-file-name-that-would-have-wrapped-over-three-lines.png") # version: none (a component test's own image)

    Admin::Slots.with("media.panel.header" => [ HeaderProbeComponent ], "media.panel.sections" => []) do
      render_inline Admin::MediaLibrary::PanelComponent.new(asset: asset.reload, locale: "en")
    end

    row = page.find("#media-panel > div:first-child")
    assert_equal %w[flex gap-2 items-start pr-10], row[:class].split.sort
    assert_equal [ "h2", "b" ], row.all(:xpath, "./*").map(&:tag_name)
    heading = row.find("h2#media-panel-title")
    assert_equal %w[flex-1 leading-7 min-w-0 text-h2 text-ink truncate], heading[:class].split.sort
    assert_selector "h2#media-panel-title > span[title='#{asset.title}']", text: asset.title, exact_text: true
  end

  test "with nobody else on the image the row is the name, and presence's element is there without a group" do
    asset = create_media_asset

    as(users(:one)) { render_inline Admin::MediaLibrary::PanelComponent.new(asset: asset.reload, locale: "en") }

    row = page.find("#media-panel > div:first-child")
    assert_equal [ "h2", "div" ], row.all(:xpath, "./*", visible: :all).map(&:tag_name)
    row.assert_selector "div.hidden.flex-none.ml-auto[data-controller='admin--presence--record'] turbo-frame#presence-media-#{asset.id}", visible: :all
    row.assert_no_selector "button", visible: :all
  end

  test "with nothing registered at its slots the panel is the panel alone" do
    Admin::Slots.with("media.panel.header" => [], "media.panel.sections" => []) do
      render_inline Admin::MediaLibrary::PanelComponent.new(asset: create_media_asset, locale: "en")
    end

    assert_selector "#media-panel"
    assert_no_selector "#media-notes"
  end

  test "the panel shows a width or the preview or a box, never the original" do
    asset = create_media_asset
    asset.update_columns(width: 1600, height: 1200, preview: nil, renditions: {}) # version: none (a test's own state)

    as(media_only_viewer) { render_inline Admin::MediaLibrary::PanelComponent.new(asset: asset.reload, locale: "en") }

    assert_no_selector "img[src*='/blobs/']"
    assert_selector "[data-image-empty]"
    assert_no_match %r{/blobs/}, rendered_content
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
