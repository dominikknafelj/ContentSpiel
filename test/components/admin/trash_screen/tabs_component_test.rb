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

  # Contrast and buttons spec (Ruling 14): the current tab is the same
  # control as a selected pill, ink with paper words, its count undimmed.
  test "the current tab is ink with paper words and its count carries no opacity" do
    render_inline tabs(current: "posts")

    classes = page.find("a[aria-current=page]")["class"].split
    assert_includes classes, "bg-ink"
    assert_includes classes, "text-paper"
    assert_not_includes classes, "bg-sunken"
    assert_empty page.all("nav a span").flat_map { |span| span["class"].to_s.split }.grep(/opacity/)
  end

  private

  def tabs(current:)
    Admin::TrashScreen::TabsComponent.new(counts: COUNTS, current:, url: ->(key) { key ? "/t?type=#{key}" : "/t" })
  end
end
