require "application_system_test_case"

# Task 9's browser-only behaviour: the token reveal's copy button (and its
# visible select-the-text fallback), the related-posts picker saving
# through the post form's own autosave, the mind graph drawing and opening
# a post, and "Create starter pages" refreshing the tree.
class Admin::AiAssistantAndGraphSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
  end

  test "creating a token reveals it once, and back/reload don't show it again" do
    visit admin_api_tokens_path
    await_admin_controllers
    press "Create token"

    assert_selector "#api-token-value", text: /\A\h{64}\z/
    raw = find("#api-token-value").text
    assert_current_path admin_api_tokens_path

    # No Clipboard API (e.g. plain http off localhost): the text is
    # selected instead, and the status line says so -- no dialog.
    page.execute_script("Object.defineProperty(navigator, 'clipboard', { value: undefined, configurable: true })")
    press "Copy token"
    assert_text "the text is selected"
    assert_equal raw, page.evaluate_script("window.getSelection().toString()").strip

    press "Done"
    assert_no_selector "#api-token-value"
    page.go_back
    assert_selector "h1", text: "Connect an AI assistant"
    assert_no_text raw

    visit current_url
    assert_no_text raw
  end

  test "the related-posts picker adds and removes through autosave" do
    post_record = create_post(title: "Hub")
    other = create_post(title: "Satellite")

    visit admin_post_path(post_record)
    await_admin_controllers

    find("#post-related_post_ids").send_keys("Sat")
    within("#post-related_post_ids-results") { press "Satellite" }
    assert_selector "[data-controller~='admin--related-posts'] li", text: "Satellite"
    assert_selector "#post-save-status", text: /\ASaved \d{2}:\d{2}\z/, wait: 5
    assert_equal [ other.id ], post_record.post_relations.reload.pluck(:related_post_id)

    within("[data-controller~='admin--related-posts'] li", text: "Satellite") { press "Remove" }
    assert_text "No related posts yet."
    wait_until { post_record.post_relations.reload.empty? }
  end

  test "the mind graph draws every post and a click opens its editor" do
    a = create_post(title: "Alpha")
    b = create_post(title: "Beta")
    PostRelation.create!(post: a, related_post: b)

    visit admin_mind_graph_path
    await_admin_controllers

    assert_selector "svg g[data-post-id='#{a.id}'] text", text: "Alpha"
    assert_selector "svg line", count: 1

    node = find("svg g[data-post-id='#{b.id}']")
    page.driver.browser.action.move_to(node.native).click.perform
    assert_current_path admin_post_path(b)
  end

  test "create starter pages refreshes the tree" do
    create_page(title: "Existing") # a root page, but no starter sections yet

    visit admin_root_path
    await_admin_controllers
    within(".admin-empty-state") { press "Create starter pages" }

    assert_text "Starter pages created"
    within("#tree") { assert_text "Blog" }
  end

  private

  def wait_until(timeout: 5)
    deadline = Time.current + timeout
    until yield
      raise "condition not met within #{timeout}s" if Time.current > deadline

      sleep 0.05
    end
  end
end
