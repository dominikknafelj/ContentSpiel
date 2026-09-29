require "test_helper"

class Admin::Columns::ImageColumnComponentTest < ViewComponent::TestCase
  include ActiveJob::TestHelper

  test "renders a file input named after the column" do
    render_inline Admin::Columns::ImageColumnComponent.new(name: "hero_image", value: nil)

    assert_selector "input[type=file][name=hero_image]"
  end

  test "renders a preview of the current image when one is attached" do
    render_inline Admin::Columns::ImageColumnComponent.new(name: "hero_image", value: create_media_asset.file)

    assert_selector "img"
  end

  test "no preview when nothing is attached" do
    render_inline Admin::Columns::ImageColumnComponent.new(name: "hero_image", value: nil)

    refute_selector "img"
  end

  # Task 5 brief: the admin thumbnail uses the `w480` variant once it's
  # ready, not the full original -- `create_media_asset`'s upload is never
  # processed (no job runner in a component test), so this asserts the
  # fallback half; the w480-once-ready half is `Media::PictureComponent
  # Test`'s own job, which already proves `Media::Asset#srcset` returns the
  # right path -- this component just has to hand `image_tag` whatever that
  # path is instead of the original when one's ready.
  test "an unprocessed asset falls back to its original file" do
    asset = create_media_asset
    render_inline Admin::Columns::ImageColumnComponent.new(name: "hero_image", value: asset.file)

    assert_selector "img[src='#{asset.url}']"
  end

  # `wide.png` is a real 3000x2000 PNG (`test/models/media/asset_test.rb`'s
  # own fixture) -- once its `w480` variant has actually processed, the
  # thumbnail switches to it rather than the (much larger) original.
  test "a processed asset's thumbnail is its w480 variant, not the original" do
    asset = create_media_asset(filename: "wide.png")
    asset.file.analyze
    perform_enqueued_jobs

    render_inline Admin::Columns::ImageColumnComponent.new(name: "hero_image", value: asset.file)

    w480_url, = asset.srcset.find { |_url, width| width == 480 }
    assert_selector "img[src='#{w480_url}']"
  end

  # `SiteSetting#logo` reaches this same component (the settings form) but
  # has no `w480` named variant registered on its own attachment --
  # `value.variant(:w480)` would raise `ArgumentError` against it
  # (`ActiveStorage::Attachment#transformations_by_name`). This proves the
  # component recognizes "not a library `Media::Asset`" and renders the
  # original instead of blowing up.
  test "a non-library attachment (the site logo) renders its original, not a w480 variant lookup" do
    site = site_settings(:default)
    site.logo.attach(io: File.open(file_fixture("tiny.png")), filename: "tiny.png", content_type: "image/png")

    render_inline Admin::Columns::ImageColumnComponent.new(name: "logo", value: site.logo)

    assert_selector "img[src*='tiny.png']"
  end
end
