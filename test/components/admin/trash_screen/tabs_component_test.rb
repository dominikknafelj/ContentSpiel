require "test_helper"

class Admin::TrashScreen::TabsComponentTest < ViewComponent::TestCase
  COUNTS = { "page" => 2, "post" => 5, "media" => 0 }.freeze

  test "four tabs, All being the sum, each a link to its own type" do
    render_inline tabs(current: nil)

    assert_equal [ "All 7", "Pages 2", "Posts 5", "Images 0" ], page.all("nav[aria-label='Filter by type'] a").map { |a| a.text.squish }
    assert_selector "a[href='/t']", text: "All"
    assert_selector "a[href='/t?type=pages']", text: "Pages"
    assert_selector "a[href='/t?type=images']", text: "Images"
  end

  test "marks the current tab" do
    render_inline tabs(current: "posts")

    assert_selector "a[aria-current=page]", count: 1
    assert_selector "a[aria-current=page]", text: "Posts"
  end

  private

  def tabs(current:)
    Admin::TrashScreen::TabsComponent.new(counts: COUNTS, current:, url: ->(key) { key ? "/t?type=#{key}" : "/t" })
  end
end
