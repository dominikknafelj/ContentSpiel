require "test_helper"

class Blocks::ImageComponentTest < ActiveSupport::TestCase
  include ComponentTestHelper

  test "alt and caption fall back along the fallback chain" do
    with_locales(%w[en de], default: "en") do
      page = root_page
      block = page.content_blocks.create!(block_type: :image, position: 0, media_asset: create_media_asset)
      block.alt = "A bright room"
      block.caption = "Our studio"
      block.save!

      I18n.with_locale(:de) do
        render_inline(Blocks::ImageComponent.new(block: block, page: page))
      end

      assert_selector "img[alt='A bright room']"
      assert_selector "figcaption", text: "Our studio"
    end
  end

  # The block's own per-use alt/caption win; the library image's defaults
  # fill in where the block leaves them blank (media library spec §3.3).
  test "the asset's own alt and caption are the defaults behind the block's overrides" do
    asset = create_media_asset
    asset.update!(alt: "Library alt", caption: "Library caption")
    block = root_page.content_blocks.create!(block_type: :image, position: 0, media_asset: asset, caption: "Block caption")

    render_inline(Blocks::ImageComponent.new(block: block, page: root_page))

    assert_selector "img[alt='Library alt']"
    assert_selector "figcaption", text: "Block caption"
  end

  # Final fix wave (I1): a block's alt/caption override only the locale
  # they're written in -- an `en`-only override must not beat the asset's
  # own `de` default on a `de` page, but still beats the asset's `en` one
  # when `de` has nothing at all.
  test "an override in another locale doesn't beat the asset's default in this one" do
    asset = create_media_asset
    Mobility.with_locale(:de) { asset.update!(alt: "Deutscher Alt-Text", caption: "Deutsche Bildunterschrift") }
    Mobility.with_locale(:en) { asset.update!(alt: "English default alt") }
    block = root_page.content_blocks.create!(block_type: :image, position: 0, media_asset: asset,
      alt: "English block alt", caption: "English block caption")

    I18n.with_locale(:de) { render_inline(Blocks::ImageComponent.new(block: block, page: root_page)) }
    assert_selector "img[alt='Deutscher Alt-Text']"
    assert_selector "figcaption", text: "Deutsche Bildunterschrift"

    I18n.with_locale(:es) { render_inline(Blocks::ImageComponent.new(block: block, page: root_page)) }
    assert_selector "img[alt='English block alt']"
    assert_selector "figcaption", text: "English block caption"
  end

  test "renders nothing without an image" do
    block = root_page.content_blocks.create!(block_type: :image, position: 0, alt: "Unused")

    render_inline(Blocks::ImageComponent.new(block: block, page: root_page))

    assert_no_selector "figure"
  end

  # A theme's template may call these without the default template's guard
  # around them (theming spec §3): each answers nil for a block with no image.
  test "alt, caption and asset answer nil for a block with no image, and sizes still answers" do
    page = root_page
    block = page.content_blocks.create!(block_type: :image, position: 0)
    component = Blocks::ImageComponent.new(block: block, page: page)

    assert_nil component.send(:asset)
    assert_nil component.send(:alt)
    assert_nil component.send(:caption)
    assert_equal Blocks::ImageComponent::SIZES, component.send(:sizes)
  end

  # Not drawn at all, so not even the view annotations of development remain
  # for a section to take for content.
  test "a block with no image renders the empty string" do
    block = root_page.content_blocks.create!(block_type: :image, position: 0)

    render_inline(Blocks::ImageComponent.new(block: block, page: root_page))

    assert_equal "", rendered_content
  end
end
