require "test_helper"

# `Admin::DashboardScreen::ColumnComponent` (dashboard spec §4.2-§4.4): a
# titled list that says one sentence when it's empty, and links to a fuller
# list only when it's given one.
class Admin::DashboardScreen::ColumnComponentTest < ViewComponent::TestCase
  setup { Current.actor = users(:one) }
  teardown { Current.reset }

  test "an empty list shows its sentence instead of a list" do
    render_inline column(records: [], empty: "Nothing scheduled.")

    assert_selector "section[aria-labelledby=dashboard-drafts] h3#dashboard-drafts", text: "Drafts"
    assert_text "Nothing scheduled."
    assert_no_selector "ul"
  end

  test "lists its records, with a Show all link only when given a path" do
    post = create_post(title: "Listed", published: false)

    render_inline column(records: [ post ], show_all_path: "/cs-studio/posts?status=draft")
    assert_selector "ul li a", text: "Listed"
    assert_selector "a[href='/cs-studio/posts?status=draft']", text: /Show all/
    assert_no_text "No drafts"

    render_inline column(records: [ post ])
    assert_no_selector "a", text: /Show all/
  end

  private

  def column(records:, empty: "No drafts — start one above.", show_all_path: nil)
    feed = Struct.new(:changes) { def last_change(_record) = nil }.new
    Admin::DashboardScreen::ColumnComponent.new(title: "Drafts", id: "dashboard-drafts", records:, empty:, feed:, show_all_path:)
  end
end
