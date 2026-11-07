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
      # A prefetched filter would answer the live reload of the frame's `src`.
      assert_selector "header nav a[data-turbo-prefetch=false]", count: 3
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

  # The rows stop at five; the count says how many wait in all, under each
  # filter, and a record with both reasons once under Everything.
  test "a neutral count beside the heading says how many wait under the filter, and nothing at zero" do
    panel
    assert_no_selector "[data-waiting-total]"
    panel("threads")
    assert_no_selector "[data-waiting-total]"

    discussed = Array.new(4) { |n| create_page(title: "Discussed #{n}") }
    marked = Array.new(3) { |n| create_post(title: "Marked #{n}") }
    both = create_page(title: "Both")
    (discussed + [ both ]).each { |record| as(users(:one)) { assert Notes::Start.call(record, body: "A note").ok? } }
    (marked + [ both ]).each { |record| record.update_columns(unpublished_changes_at: Time.current) }

    { "everything" => [ 8, "8 waiting in all" ], "threads" => [ 5, "5 with open threads in all" ],
      "unpublished" => [ 4, "4 with unpublished changes in all" ] }.each do |filter, (count, label)|
      panel(filter)
      assert_selector "header h2 + [data-waiting-total].text-count.text-meta[role=img][aria-label='#{label}']", exact_text: count.to_s
      assert_no_selector "header [data-waiting-total][class*=accent]"
    end
    assert_selector "li", count: 4
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
