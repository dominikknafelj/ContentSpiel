require "test_helper"

class Admin::Columns::ImageColumnComponentTest < ViewComponent::TestCase
  test "renders a file input named after the column" do
    render_inline Admin::Columns::ImageColumnComponent.new(name: "logo", value: nil)

    assert_selector "input[type=file][name=logo]", visible: :all
  end

  test "the file input sits in the styled drop zone, not a native control" do
    render_inline Admin::Columns::ImageColumnComponent.new(name: "logo", value: nil)

    assert_selector ".admin-file-drop input[type=file][accept='image/*'][aria-label=Logo]", visible: :all
    assert_selector ".admin-file-drop label", text: "Choose file"
  end

  test "no preview when nothing is attached" do
    render_inline Admin::Columns::ImageColumnComponent.new(name: "logo", value: nil)

    refute_selector "img"
  end

  # `SiteSetting#logo` is the one field left on this component since media
  # library Task 8 (heroes and image blocks moved to
  # `Admin::Columns::MediaColumnComponent`) -- its thumbnail is simply the
  # original.
  test "the site logo renders its original file" do
    site = site_settings(:default)
    site.logo.attach(io: File.open(file_fixture("tiny.png")), filename: "tiny.png", content_type: "image/png")

    render_inline Admin::Columns::ImageColumnComponent.new(name: "logo", value: site.logo)

    assert_selector "img[src*='tiny.png']"
  end
end
