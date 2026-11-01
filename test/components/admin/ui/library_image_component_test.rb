require "test_helper"

# `Admin::Ui::LibraryImageComponent`: how CS Studio draws a library image --
# a width it made, else the ~24px preview (blurred), else a sunken box of the
# image's size. Never the original.
class Admin::Ui::LibraryImageComponentTest < ViewComponent::TestCase
  include ContentHelper

  def asset_with_size
    asset = create_media_asset
    asset.update_columns(width: 1600, height: 1200) # version: none (a test's own dimensions)
    asset.reload
  end

  test "an image whose widths exist shows the 480 width with its size" do
    asset = make_renditions!(asset_with_size, widths: [ 480, 960, 1600 ])

    render_inline Admin::Ui::LibraryImageComponent.new(asset: asset, min_width: 480)

    assert_selector "img[src='#{asset.display_url(min_width: 480)}'][width='1600'][height='1200']"
    assert_no_selector "img[src^='data:']"
    assert_no_match %r{/blobs/}, rendered_content
  end

  test "an image with no width shows its preview, blurred, with its size" do
    asset = asset_with_size
    asset.update_columns(preview: "RIFFxxxxWEBP") # version: none (a test's own preview)

    render_inline Admin::Ui::LibraryImageComponent.new(asset: asset.reload, min_width: 480)

    assert_selector "img[src^='data:image/webp;base64,'][width='1600'][height='1200'].blur-sm"
    assert_no_match %r{/blobs/}, rendered_content
  end

  test "an image with neither draws a box of its size and no img" do
    asset = asset_with_size
    asset.update_columns(preview: nil, renditions: {}) # version: none (a test's own state)

    render_inline Admin::Ui::LibraryImageComponent.new(asset: asset.reload, min_width: 480)

    assert_no_selector "img"
    assert_selector "span.bg-sunken[data-image-empty][style*='aspect-ratio: 1600 / 1200']"
    assert_no_match %r{/blobs/}, rendered_content
  end
end
