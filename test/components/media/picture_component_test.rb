require "test_helper"

# `Media::PictureComponent` (media library design spec §4, Task 5): the one
# place every image render on this site builds its `<img>` tag from. Every
# other image component (`Blocks::ImageComponent`, `RichText::ImageComponent`,
# the page hero) renders through this one, so its own contract -- what ends
# up in `srcset`, when `srcset`/`sizes` are omitted entirely, that `alt` is
# always escaped, that a missing asset renders nothing -- is pinned directly
# here rather than re-proven by every caller.
class Media::PictureComponentTest < ActiveSupport::TestCase
  include ComponentTestHelper
  include ActiveJob::TestHelper

  test "renders src, width, height, and a srcset entry per processed variant" do
    asset = processed_asset

    render_inline(Media::PictureComponent.new(asset: asset, alt: "A bright room"))

    img = page.find("img")
    assert_equal asset.src, img["src"]
    assert_equal asset.width.to_s, img["width"]
    assert_equal asset.height.to_s, img["height"]
    assert_equal "A bright room", img["alt"]
    assert_equal "lazy", img["loading"]
    assert_equal "async", img["decoding"]

    srcset = img["srcset"]
    asset.srcset.each { |url, width| assert_includes srcset, "#{url} #{width}w" }
  end

  test "the original is no candidate: a srcset holds exactly the widths made" do
    asset = processed_asset

    render_inline(Media::PictureComponent.new(asset: asset, alt: "x"))

    candidates = page.find("img")["srcset"].split(", ")
    assert_equal asset.srcset.map { |url, width| "#{url} #{width}w" }, candidates
    assert(candidates.none? { |candidate| candidate.include?("/blobs/") })
  end

  # Final fix wave (M4): lazy by default; a caller (the hero) can ask for
  # eager loading at a high fetch priority.
  test "loading and fetchpriority can be set, and default to lazy and none" do
    render_inline(Media::PictureComponent.new(asset: create_media_asset, alt: "x"))
    assert_equal "lazy", page.find("img")["loading"]
    assert_nil page.find("img")["fetchpriority"]

    render_inline(Media::PictureComponent.new(asset: create_media_asset, alt: "x", loading: "eager", fetchpriority: "high"))
    assert_equal "eager", page.find("img")["loading"]
    assert_equal "high", page.find("img")["fetchpriority"]
  end

  test "sizes is only rendered alongside a real srcset" do
    render_inline(Media::PictureComponent.new(asset: processed_asset, alt: "x", sizes: "(min-width: 768px) 768px, 100vw"))

    assert_equal "(min-width: 768px) 768px, 100vw", page.find("img")["sizes"]
  end

  # Review Focus 3: a variant that hasn't finished processing (or never
  # will -- a GIF, or a corrupt upload `Media::Asset#srcset` caught and
  # logged) must never keep the page from rendering an image at all, just
  # from offering a `srcset` for it.
  test "an unprocessed asset renders src only, with no srcset or sizes attribute" do
    asset = create_media_asset

    render_inline(Media::PictureComponent.new(asset: asset, alt: "x"))

    img = page.find("img")
    assert_equal asset.src, img["src"]
    assert_nil img["srcset"]
    assert_nil img["sizes"]
  end

  test "alt is escaped, not rendered as markup" do
    render_inline(Media::PictureComponent.new(asset: create_media_asset, alt: "<script>alert(1)</script>"))

    assert_equal "<script>alert(1)</script>", page.find("img")["alt"]
    assert_no_selector "script"
  end

  test "a css_class is applied to the img tag" do
    render_inline(Media::PictureComponent.new(asset: create_media_asset, alt: "x", css_class: "w-full rounded-cs"))

    assert_selector "img.w-full.rounded-cs"
  end

  test "a nil asset renders nothing" do
    render_inline(Media::PictureComponent.new(asset: nil, alt: "Gone"))

    assert_no_selector "img"
  end

  test "an asset whose file is somehow detached renders nothing" do
    asset = create_media_asset
    asset.file.detach

    render_inline(Media::PictureComponent.new(asset: asset, alt: "Gone"))

    assert_no_selector "img"
  end

  test "with widths the img offers only them, the middle one as src, its size and its preview as background, and no address of the original" do
    asset = processed_asset
    render_inline(Media::PictureComponent.new(asset: asset, alt: "x"))

    img = page.find("img")
    assert_equal asset.src, img["src"]
    assert_not_includes img["src"], "data:"
    assert img["srcset"].present?
    assert_match Media::PictureComponent::PREVIEW_STYLE, img["style"]
    assert_equal Media::PictureComponent.preview_style(asset.preview_data_url), img["style"]
    assert_nil img["data-image-preview"]
    assert_nil img["data-image-empty"]
    assert_no_match(%r{/blobs/}, img.native.to_s)
  end

  test "an image with alpha gets no background" do
    asset = processed_asset
    asset.update_columns(has_alpha: true) # version: none (a test's row)
    render_inline(Media::PictureComponent.new(asset: asset.reload, alt: "x"))

    assert_nil page.find("img")["style"]
  end

  test "with no width the src is the preview and the img carries its size" do
    asset = create_media_asset(filename: "wide.png")
    asset.update_columns(renditions: {}, renditions_fingerprint: nil) # version: none (a test's row)
    asset.reload
    render_inline(Media::PictureComponent.new(asset: asset, alt: "x"))

    img = page.find("img")
    assert_equal asset.preview_data_url, img["src"]
    assert_equal asset.width.to_s, img["width"]
    assert_equal asset.height.to_s, img["height"]
    assert_nil img["srcset"]
    assert_nil img["style"]
    assert img["data-image-preview"]
  end

  test "with neither the img is a sized box with its alt and no src" do
    asset = create_media_asset(filename: "wide.png")
    asset.update_columns(renditions: {}, renditions_fingerprint: nil, preview: nil) # version: none (a test's row)
    render_inline(Media::PictureComponent.new(asset: asset.reload, alt: "A room"))

    img = page.find("img")
    assert_nil img["src"]
    assert_nil img["srcset"]
    assert_equal asset.width.to_s, img["width"]
    assert_equal asset.height.to_s, img["height"]
    assert_equal "A room", img["alt"]
    assert img["data-image-empty"]
    assert_nil img["data-image-preview"]
  end

  test "it is one img and nothing around it" do
    render_inline(Media::PictureComponent.new(asset: processed_asset, alt: "x"))

    fragment = Nokogiri::HTML5.fragment(rendered_content)
    assert_equal [ "img" ], fragment.css("*").map(&:name)
    assert_equal 1, fragment.children.count(&:element?)
  end

  test "an image narrower than 480px offers its own width" do
    asset = make_renditions!(create_media_asset(filename: "tiny.png"))
    render_inline(Media::PictureComponent.new(asset: asset, alt: "x"))

    img = page.find("img")
    assert_equal [ asset.width ], img["srcset"].scan(/ (\d+)w/).flatten.map(&:to_i)
  end

  private

  # `wide.png` (test/fixtures/files) is a real 3000x2000 PNG: all four
  # configured widths are below it, so a recorded generation holds four.
  def processed_asset
    make_renditions!(create_media_asset(filename: "wide.png"))
  end
end
