require "test_helper"

# A library image field (media library Task 8): the hidden id input
# autosave sends, the thumbnail, Choose/Change and Remove.
class Admin::Columns::MediaColumnComponentTest < ViewComponent::TestCase
  include ActiveJob::TestHelper

  def render_column(asset, **options)
    render_inline Admin::Columns::MediaColumnComponent.new(
      name: "hero_image", id: "page-hero_image", html_name: "page[hero_media_asset_id]", value: asset,
      section_id: "page-hero-image-section", **options
    )
  end

  test "an empty field has an empty hidden input, Choose, and a hidden Remove" do
    render_column(nil)

    assert_selector "#page-hero-image-section[data-controller='admin--media--field']"
    assert_selector "input[type=hidden][name='page[hero_media_asset_id]'][id='page-hero_image'][value='']", visible: :all
    assert_button "Choose image"
    assert_selector "button[hidden]", text: "Remove image", visible: :all
    assert_text "No image chosen"
    assert_no_selector "input[type=file]", visible: :all
  end

  # Round 3 Task 9: no `media.upload` means no picker on the page, so the field
  # offers Remove only and says why Choose is missing.
  test "without media.upload there is no Choose, Remove stays, and the field says why" do
    asset = Media::Asset.new(title: "Lake")
    as(users(:reader)) { render_column(asset) }

    assert_no_button "Choose image"
    assert_no_button "Change image"
    assert_button "Remove image"
    assert_text "You can't choose images."
  end

  test "with media.upload the hint is not shown" do
    as(users(:one)) { render_column(nil) }

    assert_button "Choose image"
    assert_no_text "You can't choose images."
  end

  # Final fix wave (M12): a refused choice's message is announced.
  test "the error slot is a polite live region" do
    render_column(nil, errors: [ "Hero image doesn't exist" ])

    assert_selector "[aria-live='polite']", text: "Hero image doesn't exist"
  end

  test "a chosen image shows its thumbnail, title, Change and Remove" do
    asset = create_media_asset

    render_column(asset)

    assert_selector "input[type=hidden][value='#{asset.id}']", visible: :all
    assert_selector "img[src='#{asset.src}']"
    assert_text asset.title
    assert_button "Change image"
    assert_button "Remove image"
  end

  # Same thumbnail rule as the Media module's grid: the `w480` variant once
  # it's processed, not the (much larger) original.
  test "a processed image's thumbnail is its w480 variant" do
    asset = create_media_asset(filename: "wide.png")
    asset.file.analyze
    perform_enqueued_jobs

    render_column(Media::Asset.with_variants.find(asset.id))

    w480_url, = asset.srcset.find { |_url, width| width == 480 }
    assert_selector "img[src='#{w480_url}']"
  end

  test "the error slot is the column id's, where the save service reports a refused choice" do
    render_column(nil, errors: [ "Hero image doesn't exist" ])

    assert_selector "#page-hero_image-errors", text: "Hero image doesn't exist"
  end

  test "the override fields to keep in step are passed to the controller" do
    render_column(nil, placeholder_ids: { alt: "page-hero_alt" })

    assert_equal({ "alt" => "page-hero_alt" }, JSON.parse(page.find("#page-hero-image-section")["data-admin--media--field-placeholder-ids-value"]))
  end

  test "the defaults a blank override falls back to, in the editing locale" do
    asset = create_media_asset
    asset.update!(alt: "A dog", caption: "Our dog")
    Mobility.with_locale(:de) { asset.update!(alt: "Ein Hund") }

    assert_equal "Ein Hund", Admin::Columns::MediaColumnComponent.default_alt(asset, "de")
    assert_equal "A dog", Admin::Columns::MediaColumnComponent.default_alt(asset, "en")
    assert_equal "Our dog", Admin::Columns::MediaColumnComponent.default_caption(asset, "en")
    assert_equal "", Admin::Columns::MediaColumnComponent.default_alt(nil, "en")
  end
end
