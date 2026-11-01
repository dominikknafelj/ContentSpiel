require "application_system_test_case"

# An image with neither a width nor a preview is drawn as the box of the
# image's size, on the sunken ground, so the page around it does not move
# and the reader sees where the image goes: on the public site an `<img>`
# with no `src` (`data-image-empty`, sized by its own `width` and `height`
# and `images.css`), in CS Studio a `<span>` with the image's aspect ratio
# (`Admin::Ui::LibraryImageComponent`). Measured by the browser, because
# an `<img>` with no file is easily drawn zero pixels high.
class ImageBoxSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Gallery")
    @asset = create_media_asset(filename: "wide.png")
    @asset.update_columns(width: 1600, height: 900, preview: nil, renditions: {}, renditions_fingerprint: nil) # version: none (a test makes an image with no width and no preview)
    result = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "image", media_asset_id: @asset.id })
    assert result.ok?, result.errors.to_sentence
  end

  def box(selector)
    page.evaluate_script(<<~JS, selector)
      (() => {
        const element = document.querySelector(arguments[0])
        const rect = element.getBoundingClientRect()
        return { "width": rect.width, "height": rect.height, "ground": getComputedStyle(element).backgroundColor }
      })()
    JS
  end

  def assert_box_of_the_image(drawn)
    assert_operator drawn["width"], :>, 50
    assert_in_delta drawn["width"] * 900 / 1600, drawn["height"], 1.5
    assert_not_equal "rgba(0, 0, 0, 0)", drawn["ground"]
  end

  test "on a public page the empty image is a box of the image's shape on the sunken ground, also with no class, an alt text and a narrow column" do
    publish_changes(@page)
    visit PublicSite::Urls.new.path_for(@page, "en")
    assert_selector "img[data-image-empty]:not([src])", visible: :all

    assert_box_of_the_image(box("img[data-image-empty]"))

    # As a theme's own template and stylesheet could draw it: no class of
    # the CMS's, images made inline, an alt text a browser would then lay
    # out as a line of text, in a column narrower than the image.
    page.execute_script(<<~JS)
      const inline = document.createElement("style")
      inline.textContent = "img { display: inline }"
      document.head.append(inline)
      const img = document.createElement("img")
      Object.assign(img, { id: "bare", alt: "A long description of the view over the harbour", width: 1600, height: 900 })
      img.dataset.imageEmpty = ""
      const holder = document.createElement("div")
      holder.style.width = "320px"
      holder.append(img)
      document.querySelector("main").prepend(holder)
    JS
    bare = box("#bare")
    assert_box_of_the_image(bare)
    assert_in_delta 320, bare["width"], 0.5
  end

  test "in the media library the empty image is a box of the image's shape on the sunken ground" do
    sign_in_via_form(users(:one))
    visit "/cs-studio/media"
    assert_selector "[data-image-empty]", visible: :all

    drawn = box("[data-image-empty]")
    assert_operator drawn["width"], :>, 50
    assert_operator drawn["height"], :>, 10
    assert_not_equal "rgba(0, 0, 0, 0)", drawn["ground"]
  end
end
