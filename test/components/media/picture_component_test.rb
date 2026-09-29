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
    assert_equal asset.url, img["src"]
    assert_equal asset.width.to_s, img["width"]
    assert_equal asset.height.to_s, img["height"]
    assert_equal "A bright room", img["alt"]
    assert_equal "lazy", img["loading"]
    assert_equal "async", img["decoding"]

    srcset = img["srcset"]
    asset.srcset.each { |url, width| assert_includes srcset, "#{url} #{width}w" }
  end

  # Final fix wave (I3): once `srcset` has `w` descriptors a browser never
  # falls back to `src`, so without the original as a candidate a wide
  # screen would top out at the largest variant (2400px) of a larger image.
  test "the original is the widest srcset candidate once there are variants" do
    asset = processed_asset

    render_inline(Media::PictureComponent.new(asset: asset, alt: "x"))

    candidates = page.find("img")["srcset"].split(", ")
    assert_equal "#{asset.url} #{asset.width}w", candidates.last
    assert_equal asset.srcset.size + 1, candidates.size
  end

  test "without a known width the original isn't offered as a candidate" do
    asset = processed_asset
    asset.update_columns(width: nil, height: nil)

    render_inline(Media::PictureComponent.new(asset: asset, alt: "x"))

    assert_not_includes page.find("img")["srcset"], "#{asset.url} "
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
    assert_equal asset.url, img["src"]
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

  private

  # `wide.png` (test/fixtures/files) is a real 3000x2000 PNG -- every
  # declared variant width (480/960/1600/2400) is smaller than that, so all
  # four end up in `srcset` once the preprocessing jobs run
  # (`test/models/media/asset_test.rb`'s own fixture and pattern).
  def processed_asset
    asset = create_media_asset(filename: "wide.png")
    asset.file.analyze
    metadata = asset.file.blob.metadata || {}
    asset.update_columns(width: metadata["width"], height: metadata["height"])
    perform_enqueued_jobs
    asset
  end
end
