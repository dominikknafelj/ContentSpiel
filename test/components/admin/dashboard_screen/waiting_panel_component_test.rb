require "test_helper"

# `Admin::DashboardScreen::WaitingPanelComponent`: Waiting for you, an action
# panel in a frame of its own, with its filter as three links that navigate
# the frame.
class Admin::DashboardScreen::WaitingPanelComponentTest < ViewComponent::TestCase
  setup { Current.actor = users(:two) }
  teardown { Current.reset }

  def waiting(filter = "everything") = Dashboard::WaitingForYou.new(actor: users(:two), filter:, channel: :admin)

  def panel(filter = "everything") = render_inline(Admin::DashboardScreen::WaitingPanelComponent.new(waiting: waiting(filter)))

  test "a frame around an action panel headed by its job, its filter in the head" do
    panel

    assert_selector "turbo-frame#dashboard-waiting.contents > section.admin-dashboard-panel--action[aria-labelledby=dashboard-waiting-title]" do
      assert_selector "header h2#dashboard-waiting-title", exact_text: "Waiting for you"
      assert_selector "header .admin-dashboard-panel__line", exact_text: "Open threads and changes that are not on the site yet."
      assert_selector "header nav[aria-label=Show] a[data-turbo-frame=dashboard-waiting]", count: 3
      assert_equal [ "Everything", "Open threads", "Unpublished changes" ], page.all("nav a").map { |link| link.text.strip }
      assert_equal %w[/cs-studio/dashboard/waiting?filter=everything /cs-studio/dashboard/waiting?filter=threads /cs-studio/dashboard/waiting?filter=unpublished],
        page.all("nav a").map { |link| link[:href] }
    end
  end

  test "the current filter is the query's, and the empty line is the filter's" do
    { "everything" => [ "Everything", "Nothing is waiting for you." ], "threads" => [ "Open threads", "No open threads." ],
      "unpublished" => [ "Unpublished changes", "No unpublished changes." ], "nonsense" => [ "Everything", "Nothing is waiting for you." ] }.each do |filter, (current, empty)|
      panel(filter)
      assert_selector "nav a[aria-current=page]", count: 1, text: current
      assert_selector "p[data-panel-empty]", exact_text: empty
    end
  end

  test "every row is a waiting row" do
    page_record = create_page(title: "Marked")
    page_record.update_columns(unpublished_changes_at: Time.current)
    as(users(:one)) { assert Notes::Start.call(create_post(title: "Discussed"), body: "A note").ok? }

    panel

    assert_selector "li > .admin-waiting-row", count: 2
    assert_no_selector "p[data-panel-empty]"
  end
end
