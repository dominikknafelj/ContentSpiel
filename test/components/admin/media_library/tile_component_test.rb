require "test_helper"

class Admin::MediaLibrary::TileComponentTest < ViewComponent::TestCase
  include ContentHelper

  test "an image with no alt and no use carries both chips, as words" do
    asset = create_media_asset

    render_inline Admin::MediaLibrary::TileComponent.new(asset: asset, url: "/cs-studio/media?selected=#{asset.id}", unused: true)

    assert_selector "li#media-asset-#{asset.id} a[href='/cs-studio/media?selected=#{asset.id}']"
    assert_text "No alt"
    assert_text "Unused"
  end

  test "the size shows in mono once the dimensions are known" do
    asset = create_media_asset
    asset.update_columns(width: 1600, height: 1200)

    render_inline Admin::MediaLibrary::TileComponent.new(asset: asset.reload, url: "/x", unused: false)

    assert_text "1600×1200"
  end

  test "an image with an alt text in the default language and a use has no chips" do
    asset = create_media_asset
    assert Media::Save.call(asset, translations: { Locales.default => { alt: "Sand dunes" } }).ok?

    render_inline Admin::MediaLibrary::TileComponent.new(asset: asset.reload, url: "/x", unused: false)

    assert_no_text "No alt"
    assert_no_text "Unused"
  end

  test "an alt text only in another language is still No alt" do
    with_locales(%w[en de], default: "en")
    asset = create_media_asset
    assert Media::Save.call(asset, translations: { "de" => { alt: "Düne" } }).ok?

    render_inline Admin::MediaLibrary::TileComponent.new(asset: asset.reload, url: "/x", unused: false)

    assert_text "No alt"
  end

  test "the selected tile has aria-current and the accent ring; others have neither" do
    asset = create_media_asset

    render_inline Admin::MediaLibrary::TileComponent.new(asset: asset, url: "/x", unused: false, selected: true)
    assert_selector "a[aria-current='true'].ring-accent-tint"

    render_inline Admin::MediaLibrary::TileComponent.new(asset: asset, url: "/x", unused: false)
    assert_no_selector "a[aria-current]"
  end

  test "the link targets the content frame and advances the URL" do
    render_inline Admin::MediaLibrary::TileComponent.new(asset: create_media_asset, url: "/x", unused: false)

    assert_selector "a[data-turbo-frame='content'][data-turbo-action='advance']"
  end

  # The picker's tile is a button that selects, not a link.
  test "a pick tile is a button with the picker's id, the select actions and the payload" do
    asset = create_media_asset
    Mobility.with_locale(:en) { asset.update!(alt: "A dune", caption: "At dusk") }

    render_inline Admin::MediaLibrary::TileComponent.new(asset: asset.reload, unused: true, pick: true, locale: "en")

    assert_no_selector "a"
    assert_selector "li#media-picker-asset-#{asset.id} button[type=button][aria-pressed=false][data-asset-id='#{asset.id}']"
    button = page.find("button")
    assert_includes button["data-action"], "click->admin--media--select#select"
    assert_includes button["data-action"], "dblclick->admin--media--select#choose"
    assert_includes button["data-action"], "keydown->admin--media--select#key"
    assert_equal({ "id" => asset.id, "url" => asset.thumbnail_url, "width" => asset.width, "height" => asset.height, "preview" => true, "title" => asset.title, "alt" => "A dune", "caption" => "At dusk" },
      JSON.parse(button["data-admin--media--select-asset-param"]))
    assert_text "Unused"
  end

  test "a pick tile draws its selection from aria-pressed, with the same ring the panel's tile has" do
    asset = create_media_asset

    render_inline Admin::MediaLibrary::TileComponent.new(asset: asset, unused: false, pick: true)

    assert_selector "button.aria-pressed\\:ring-accent-tint.aria-pressed\\:border-accent"
  end

  test "a tile of an image whose widths exist shows the 480 width with its size, never the original" do
    asset = create_media_asset
    asset.update_columns(width: 1600, height: 1200) # version: none (a test's own dimensions)
    asset = make_renditions!(asset.reload, widths: [ 480, 960, 1600 ])

    render_inline Admin::MediaLibrary::TileComponent.new(asset: asset, url: "/x", unused: false)

    assert_selector "img[src='#{asset.display_url(min_width: 480)}'][width='1600'][height='1200']"
    assert_no_match %r{/blobs/}, rendered_content
  end

  test "a tile of an image with neither a width nor a preview is a box, not the original" do
    asset = create_media_asset
    asset.update_columns(width: 1600, height: 1200, preview: nil, renditions: {}) # version: none (a test's own state)

    render_inline Admin::MediaLibrary::TileComponent.new(asset: asset.reload, url: "/x", unused: false)

    assert_no_selector "img"
    assert_selector "[data-image-empty]"
    assert_no_match %r{/blobs/}, rendered_content
  end

  test "open notes are the shared bubble on the image, unread says 2 new and is named new for you, and none draws nothing" do
    asset = create_media_asset

    render_inline Admin::MediaLibrary::TileComponent.new(asset: asset, url: "/x", unused: false, open_notes: 2)
    assert_selector "span.admin-notes-marker.admin-notes-marker--on-image[data-notes-chip][data-has-notes][role=img][aria-label='2 open notes']", text: "2"
    assert_no_selector "[data-unread]"

    render_inline Admin::MediaLibrary::TileComponent.new(asset: asset, url: "/x", unused: false, open_notes: 2, notes_unread: true)
    assert_selector ".admin-notes-marker--on-image[data-unread][aria-label='2 open notes, new for you']", text: "2 new"

    render_inline Admin::MediaLibrary::TileComponent.new(asset: asset, url: "/x", unused: false)
    assert_no_selector ".admin-notes-marker"
  end
end
