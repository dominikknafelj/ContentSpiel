require "test_helper"

# "Waiting for you" on the dashboard: one frame, `turbo-frame#dashboard-waiting`,
# that its filter's links navigate and a live note reloads
# (`Admin::DashboardController#waiting`).
class Admin::DashboardWaitingTest < ActionDispatch::IntegrationTest
  FRAME = { "Turbo-Frame" => "dashboard-waiting" }.freeze

  setup do
    with_locales(%w[en de], default: "en")
    sign_in_as users(:two)
  end

  def mark(record) = record.update_columns(unpublished_changes_at: Time.current)

  def note(record) = as(users(:one)) { assert Notes::Start.call(record, body: "A note").ok? }

  test "the dashboard draws Waiting for you in its own frame, with Everything chosen" do
    get admin_root_path(locale: "de")

    assert_select "turbo-frame#dashboard-waiting section.admin-dashboard-panel--action[aria-labelledby=dashboard-waiting-title]" do
      assert_select "h2", "Waiting for you"
      assert_select ".admin-dashboard-panel__line", "Open threads and changes that are not on the site yet."
      assert_select "nav[aria-label=Show] a[aria-current=page]", count: 1, text: "Everything"
      assert_select "nav[aria-label=Show] a[data-turbo-frame=dashboard-waiting]", count: 3
      assert_equal %w[everything threads unpublished].map { |filter| admin_dashboard_waiting_path(filter:, locale: "de") },
        css_select("nav[aria-label=Show] a").map { |link| link["href"] }
      assert_select "p[data-panel-empty]", "Nothing is waiting for you."
    end
    assert_select "#notes-open-threads, #dashboard-open-threads, #dashboard-unpublished-changes", count: 0
  end

  test "each filter is answered by the frame alone" do
    discussed = create_page(title: "Discussed")
    note(discussed)
    marked = create_post(title: "Marked")
    mark(marked)

    get admin_dashboard_waiting_path(filter: "unpublished"), headers: FRAME

    assert_response :ok
    assert_no_match(/<html/, response.body)
    assert_select "#sidebar", count: 0
    assert_select "turbo-frame#dashboard-waiting" do
      assert_select "nav[aria-label=Show] a[aria-current=page]", count: 1, text: "Unpublished changes"
      assert_select ".admin-waiting-row", count: 1
      assert_select ".admin-waiting-row a[href='#{admin_post_path(marked)}']", text: "Marked"
      assert_select ".admin-waiting-row", text: /Discussed/, count: 0
    end

    get admin_dashboard_waiting_path(filter: "threads"), headers: FRAME
    assert_select "turbo-frame#dashboard-waiting .admin-waiting-row", count: 1, text: /Discussed/
    assert_select "nav[aria-label=Show] a[aria-current=page]", text: "Open threads"

    sign_in_as User.create!(email_address: "nobody@example.com", password: "a long enough password")
    get admin_dashboard_waiting_path(filter: "threads"), headers: FRAME
    assert_select "turbo-frame#dashboard-waiting p[data-panel-empty]", "No open threads."
    get admin_dashboard_waiting_path(filter: "unpublished"), headers: FRAME
    assert_select "turbo-frame#dashboard-waiting p[data-panel-empty]", "No unpublished changes."
  end

  test "an unknown filter is answered as Everything" do
    marked = create_post(title: "Marked")
    mark(marked)

    [ { filter: "bogus" }, { filter: [ "threads" ] }, { filter: { a: 1 } } ].each do |params|
      get admin_dashboard_waiting_path(params), headers: FRAME
      assert_response :ok, params.inspect
      assert_select "nav[aria-label=Show] a[aria-current=page]", { count: 1, text: "Everything" }, params.inspect
      assert_select ".admin-waiting-row", text: /Marked/
    end
  end

  test "the panel's address outside a frame goes to the dashboard" do
    get admin_dashboard_waiting_path(filter: "threads")
    assert_redirected_to admin_root_path
    assert_response :see_other

    get admin_dashboard_waiting_path(locale: "de"), headers: { "Turbo-Frame" => "notes-for-you" }
    assert_redirected_to admin_root_path(locale: "de")
  end

  test "notes/open_threads is gone" do
    get "/#{ContentSpiel::ADMIN_PATH}/notes/open_threads"
    assert_response :not_found
    assert_not Rails.application.routes.url_helpers.respond_to?(:admin_open_note_threads_path)
  end

  # Every kind a row can be, the newest set made last so that the five rows
  # shown are of the same kinds with one set as with twenty: an image's
  # thread, a page's thread, a page and a post the feed alone brings, and a
  # post with both reasons, for a viewer who may publish pages and posts.
  test "Waiting for you costs the same statements with one set of every kind as with twenty" do
    counts = [ 1, 20 ].map do |n|
      n.times do |i|
        note(create_media_asset)
        note(create_page(title: "Discussed #{n}-#{i}"))
        mark(create_page(title: "Marked page #{n}-#{i}"))
        mark(create_post(title: "Marked post #{n}-#{i}"))
        create_post(title: "Both #{n}-#{i}").tap { |post| note(post) }.then { |post| mark(post) }
      end
      get admin_dashboard_waiting_path, headers: FRAME # warm-up
      statements = capture_sql { get admin_dashboard_waiting_path, headers: FRAME }.size
      assert_select ".admin-waiting-row", count: 5
      assert_select ".admin-waiting-row a", text: "Review and publish…", count: 3
      assert_select ".admin-waiting-row .admin-notes-marker", count: 3
      assert_select "[data-waiting-total]", text: { 1 => "5", 20 => "105" }.fetch(n)
      statements
    end

    assert_equal counts.first, counts.last
    # 15 for the rows, and 3 for the count beside the heading: the threads'
    # records in one statement and the unpublished ones in one per model.
    assert_operator counts.last, :<=, 18, "Waiting for you's statements: #{counts.last}"
  end
end
