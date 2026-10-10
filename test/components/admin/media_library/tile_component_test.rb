require "test_helper"

class Admin::MediaLibrary::TileComponentTest < ViewComponent::TestCase
  include ContentHelper

  test "an image with no alt and no use carries both chips, as words" do
    asset = create_media_asset

    render_inline Admin::MediaLibrary::TileComponent.new(asset: asset, url: "/cs-studio/media?selected=#{asset.id}", unused: true)

    assert_selector "li#media-asset-#{asset.id} a[href='/cs-studio/media?selected=#{asset.id}']"
    assert_text "NO ALT"
    assert_text "UNUSED"
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

    assert_no_text "NO ALT"
    assert_no_text "UNUSED"
  end

  test "an alt text only in another language is still NO ALT" do
    with_locales(%w[en de], default: "en")
    asset = create_media_asset
    assert Media::Save.call(asset, translations: { "de" => { alt: "Düne" } }).ok?

    render_inline Admin::MediaLibrary::TileComponent.new(asset: asset.reload, url: "/x", unused: false)

    assert_text "NO ALT"
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

  # Round 3 Task 9: the picker's tile is a button that selects, not a link.
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
    assert_equal({ "id" => asset.id, "url" => asset.thumbnail_url, "title" => asset.title, "alt" => "A dune", "caption" => "At dusk" },
      JSON.parse(button["data-admin--media--select-asset-param"]))
    assert_text "UNUSED"
  end

  test "a pick tile draws its selection from aria-pressed, with the same ring the panel's tile has" do
    asset = create_media_asset

    render_inline Admin::MediaLibrary::TileComponent.new(asset: asset, unused: false, pick: true)

    assert_selector "button.aria-pressed\\:ring-accent-tint.aria-pressed\\:border-accent"
  end
end
