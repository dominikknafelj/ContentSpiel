require "test_helper"

class Admin::Columns::ImageColumnComponentTest < ViewComponent::TestCase
  test "renders a file input named after the column" do
    render_inline Admin::Columns::ImageColumnComponent.new(name: "hero_image", value: nil)

    assert_selector "input[type=file][name=hero_image]"
  end

  test "renders a preview of the current image when one is attached" do
    page = root_page
    page.hero_image.attach(io: StringIO.new("fake"), filename: "hero.png", content_type: "image/png")

    render_inline Admin::Columns::ImageColumnComponent.new(name: "hero_image", value: page.hero_image)

    assert_selector "img"
  end

  test "no preview when nothing is attached" do
    render_inline Admin::Columns::ImageColumnComponent.new(name: "hero_image", value: nil)

    refute_selector "img"
  end

  private

  def root_page
    Page.find_by(parent_id: nil) || Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
  end
end
