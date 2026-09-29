require "test_helper"

class Admin::Columns::ImageColumnComponentTest < ViewComponent::TestCase
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
end
