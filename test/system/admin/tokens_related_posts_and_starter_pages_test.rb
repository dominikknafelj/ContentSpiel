require "application_system_test_case"

# Three behaviours that only a browser shows, each small enough to share a
# file: the token reveal's copy button (and its visible select-the-text
# fallback), the related-posts picker saving through the post form's own
# autosave, and "Create starter pages" refreshing the tree. (The mind graph's
# tests are in `test/system/admin/mind_graph_test.rb` and
# `mind_graph_modules_test.rb`.)
class Admin::TokensRelatedPostsAndStarterPagesSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
  end

  test "creating a token reveals it once, and back/reload don't show it again" do
    visit admin_api_tokens_path
    await_admin_controllers

    # The group's description sits under the select and follows it.
    assert_selector "#token-group-description", text: access_control_groups(:read_only).description.to_s
    fill_in "Name", with: "claude-desktop"
    select "Admin", from: "Group"
    assert_selector "#token-group-description", text: access_control_groups(:admin).description

    press "Create token"

    assert_selector "#api-token-value", text: /\A\h{64}\z/
    raw = find("#api-token-value").text
    assert_current_path admin_api_tokens_path
    assert_text "Copy this token now. It won't be shown again."
    assert_selector "#api-token-config", text: raw
    assert_selector "table", text: "claude-desktop"

    # No Clipboard API (e.g. plain http off localhost): the text is
    # selected instead, and the status line says so -- no dialog.
    page.execute_script("Object.defineProperty(navigator, 'clipboard', { value: undefined, configurable: true })")
    press "Copy token"
    assert_text "the text is selected"
    assert_equal raw, page.evaluate_script("window.getSelection().toString()").strip

    # Leaving and coming Back refetches the list: the token is gone, its name stays.
    visit admin_root_path
    assert_no_selector "#api-token-value"
    page.go_back
    assert_selector "h1", text: "Connect an AI assistant"
    assert_no_text raw
    assert_selector "table", text: "claude-desktop"

    visit admin_api_tokens_path
    assert_no_text raw
    assert_selector "table", text: "claude-desktop"
  end

  test "the related-posts picker adds and removes through autosave" do
    post_record = create_post(title: "Hub")
    other = create_post(title: "Satellite")

    visit admin_post_path(post_record)
    await_admin_controllers

    find("#post-related_post_ids").send_keys("Sat")
    # A native click (not `press`), the way an editor picks: the list's own
    # mousedown handler keeps focus in the search box, so nothing blurs (and
    # nothing autosaves) before the click lands.
    within("#post-related_post_ids-listbox") { find("[role=option]", text: "Satellite").click }
    assert_selector "[data-controller~='admin--ui--chip-input'] li", text: "Satellite"
    assert_selector "#post-save-status", text: /\A(● )?SAVED( · NOT PUBLISHED)? \d{2}:\d{2}\z/, wait: 5
    assert_equal [ other.id ], post_record.post_relations.reload.pluck(:related_post_id)

    find("[data-controller~='admin--ui--chip-input'] button[aria-label='Remove Satellite']").click
    assert_no_selector "[data-controller~='admin--ui--chip-input'] li", text: "Satellite"
    assert_eventually { post_record.post_relations.reload.empty? }
  end

  test "create starter pages refreshes the tree" do
    # Starter pages are offered only while Home is the only kept page (design
    # pass bug 4), so this starts from a site with nothing but Home.
    root_page

    visit admin_pages_path # opens Home's editor
    await_admin_controllers
    within("#tree") do
      find("button[aria-label='More page actions']").click
      press "Create starter pages"
    end

    # The answer to this press is the slowest in CS Studio: the POST writes
    # three pages, their posts and blocks and every derived row (568
    # statements, 0.4 s on an idle laptop), and its redirect then renders the
    # whole editor again. On a two-core runner or a loaded machine that is
    # more than Capybara's default 2 s, and nothing was wrong: the failure's
    # screenshot showed the old page with Turbo's progress bar still running
    # (the same failure comes from delaying `StarterContents::Add` by 1.6 s).
    # An answer that lands just as the 2 s run out can read as an Error
    # instead, "Unable to find visible xpath /html": the last poll has found
    # <html>, the visit resets Chrome's node ids before it is read
    # (`StaleNodeAtOnce`), and Capybara reports a stale node as not found.
    assert_text "Starter pages created", wait: 10
    within("#tree") { assert_text "Blog" }
  end
end
