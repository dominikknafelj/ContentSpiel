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

  # The tabs are the shared segmented control's links, the same control as a
  # selected pill, its count undimmed.
  test "the tabs are the shared segmented control's links and a count carries no opacity" do
    render_inline tabs(current: "posts")

    assert_equal Admin::Ui::SegmentedComponent::LINK_SEGMENT_CLASS, page.find("a[aria-current=page]")["class"]
    assert_empty page.all("nav a span").flat_map { |span| span["class"].to_s.split }.grep(/opacity/)
  end

  private

  def tabs(current:)
    Admin::TrashScreen::TabsComponent.new(counts: COUNTS, current:, url: ->(key) { key ? "/t?type=#{key}" : "/t" })
  end
end
