require "test_helper"

class Admin::JumpControllerTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @post = create_post(title: "Jumpmatch post")
  end

  test "signed out redirects to sign-in" do
    get admin_jump_path(q: "jump")
    assert_redirected_to admin_sign_in_path
  end

  test "a matching post is a link, in a bare fragment without the layout" do
    sign_in_as users(:one)
    get admin_jump_path(q: "jumpmatch")
    assert_response :success
    assert_select "turbo-frame#jump-results a[href=?]", admin_post_path(@post), text: /Jumpmatch post/
    assert_select "nav[aria-label=Modules]", count: 0
  end

  # The view resolves a row's route name against `Admin::JumpHelper::JUMP_ROUTES`
  # and refuses any other: every route the query can produce must be on it.
  test "every route a row can carry is on the helper's list" do
    names = Jump::Search::ACTIONS.map { |action| action[:path] } +
      Jump::Search::SETTINGS_DESTINATIONS.map { |destination| destination[:path] } +
      Admin::BaseController::MODULES.map { |entry| entry[:path] } +
      %i[admin_page_path admin_post_path admin_media_path]

    assert_empty names.uniq - Admin::JumpHelper::JUMP_ROUTES
  end

  test "a percent sign is literal text and finds no post" do
    sign_in_as users(:one)
    get admin_jump_path(q: "%")
    assert_response :success
    assert_select "a[href=?]", admin_post_path(@post), count: 0
    assert_select "p", text: /No results for/
    assert_select "a[href=?]", new_admin_post_path, text: "New post"
  end

  test "the New page and New post actions are links that close the palette and open their dialogs" do
    sign_in_as users(:one)
    get admin_jump_path(q: "new p")

    %w[page post].each do |kind|
      assert_select "a[href=?][data-action='admin--command-palette#close admin--ui--dialog#open'][data-admin--ui--dialog-id-param=?]",
        public_send("new_admin_#{kind}_path"), "new-#{kind}-dialog", text: /New #{kind}/
    end
    assert_select "a[data-admin--ui--dialog-id-param]", count: 2
  end

  test "the fragment echoes the trimmed, capped query it answered" do
    sign_in_as users(:one)
    get admin_jump_path(q: "  jumpmatch  ")
    assert_select "#jump-results [data-query=?]", "jumpmatch"
    get admin_jump_path(q: "a" * 500)
    assert_select "#jump-results [data-query=?]", "a" * 100
  end

  test "an overlong or non-string query is a short search, not an error" do
    sign_in_as users(:one)
    get admin_jump_path(q: "a" * 500)
    assert_response :success
    get "#{admin_jump_path}?q[]=x"
    assert_response :success
  end

  test "a title containing markup is escaped" do
    create_post(title: "<script>alert(1)</script>")
    sign_in_as users(:one)
    get admin_jump_path(q: "alert")
    assert_response :success
    assert_not_includes response.body, "<script>alert(1)</script>"
    assert_includes response.body, "&lt;script&gt;alert(1)&lt;/script&gt;"
  end

  test "an empty query lists modules and actions" do
    sign_in_as users(:one)
    get admin_jump_path
    assert_select "[role=group] > [role=presentation]", text: "Sections"
    assert_select "[role=group] > [role=presentation]", text: "Settings"
    assert_select "[role=group] > [role=presentation]", text: "Actions"
  end

  # One listbox (what the palette's combobox input controls), holding groups
  # each named by its own heading row, holding options that each have an id
  # (for `aria-activedescendant`).
  test "the results are one listbox of labelled groups whose options have unique ids" do
    sign_in_as users(:one)
    get admin_jump_path
    assert_select "#jump-listbox[role=listbox]", count: 1
    assert_select "[role=listbox]", count: 1

    groups = css_select("#jump-listbox > [role=group]")
    assert_operator groups.size, :>=, 2
    groups.each do |group|
      assert_select group, "> [role=presentation]##{group["aria-labelledby"]}", count: 1
      assert_select group, "> [role=option]", minimum: 1
    end

    ids = css_select("#jump-listbox [role=option]").map { |option| option["id"] }
    assert ids.all?(&:present?)
    assert_equal ids.uniq, ids
  end

  test "no results still renders the (empty) listbox the input controls" do
    sign_in_as users(:one)
    get admin_jump_path(q: "zzzqqq")
    assert_select "#jump-listbox[role=listbox]", count: 1
    assert_select "#jump-listbox [role=option]", count: 0
  end

  test "a user with no grants sees only what they can read" do
    nobody = User.create!(email_address: "nogrants@example.com", password: "a long enough password")
    sign_in_as nobody
    get admin_jump_path(q: "jumpmatch")
    assert_response :success
    assert_select "a[href=?]", admin_post_path(@post), count: 0
  end

  test "a draft post shows its status chip, a live one none, and every row carries the selected-row Enter hint" do
    sign_in_as users(:one)
    create_post(title: "Jumpdraft", published: false)
    create_post(title: "Jumplive", published: true)
    get admin_jump_path(q: "jump")
    assert_select "[role=option]", text: /Jumpdraft/ do
      assert_select ".admin-status-chip[data-status=draft]", count: 1
    end
    assert_select "[role=option]", text: /Jumplive/ do
      assert_select ".admin-status-chip", count: 0
    end
    assert_select "[role=option] .admin-palette__enter", minimum: 2
  end

  test "Settings destinations anchor into the settings screen" do
    sign_in_as users(:one)
    get admin_jump_path(q: "publishing")
    assert_select "[role=option] a[href$='/settings#publishing']", text: /Settings › Publishing/
  end
end
