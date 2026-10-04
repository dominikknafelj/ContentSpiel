require "application_system_test_case"

# The editor header in a real browser (design pass round 2, Task 4): one
# primary action, the ⋯ menu's keyboard behaviour, and publish / unpublish
# refreshing the whole screen (the tree included) because their forms leave
# the content frame.
class EditorHeaderSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    Current.set(actor: users(:one)) { @draft = create_page(title: "Draft idea", published: false) }
  end

  test "publish from the one primary button, then unpublish from the menu" do
    sign_in_via_form(users(:one))
    visit admin_page_path(@draft)
    await_admin_controllers

    header = "header.admin-editor-header"
    assert_selector "#{header} .admin-status-chip[data-status=draft]"
    assert_selector "#{header} button.bg-accent", count: 1
    assert_selector "#{header} button.bg-accent", text: "Publish"

    # The tree shows the draft's chip before publishing.
    assert_selector "li[data-page-id='#{@draft.id}'] .admin-status-chip[data-status=draft]", wait: 5

    # Keyboard: focus the ⋯ button, Enter opens the menu on its first item,
    # ArrowDown reaches "Schedule…" (after Activity), Escape closes it and
    # hands focus back to the button.
    page.execute_script("document.querySelector(\"#{header} button[aria-label='More actions']\").focus()")
    page.driver.browser.keyboard.type(:Enter)
    assert_selector "#{header} [role=menu]"
    assert_equal "Activity", page.evaluate_script("document.activeElement.textContent.trim()")
    page.driver.browser.keyboard.type(:Down)
    assert_equal "Schedule…", page.evaluate_script("document.activeElement.textContent.trim()")
    page.driver.browser.keyboard.type(:Escape)
    assert_no_selector "#{header} [role=menu]"
    assert_equal "More actions", page.evaluate_script("document.activeElement.getAttribute('aria-label')")

    find("#{header} button.bg-accent", text: "Publish").click

    # The publish form targets `_top`: a full visit, so everything re-renders.
    assert_selector "#{header} .admin-status-chip[data-status=live]", wait: 10
    assert_no_selector "#{header} button.bg-accent"
    assert_selector "#{header} [role=status]", text: "This page is live. Changes appear on the site as soon as they’re saved."
    assert_no_selector "li[data-page-id='#{@draft.id}'] .admin-status-chip[data-status=draft]"
    assert @draft.reload.live?

    await_admin_controllers
    open_editor_menu
    press "Unpublish"
    within("dialog#unpublish-page-#{@draft.id}[open]") do
      assert_text "Unpublish this page?"
      press "Unpublish"
    end

    assert_selector "#{header} .admin-status-chip[data-status=draft]", wait: 10
    assert_selector "#{header} button.bg-accent", text: "Publish"
    assert_not @draft.reload.live?
  end

  test "Schedule… in the menu reveals the (interim) schedule form" do
    sign_in_via_form(users(:one))
    visit admin_page_path(@draft)
    await_admin_controllers

    assert_no_selector ".admin-editor-header__schedule input[name=published_at]"
    open_editor_menu
    press "Schedule…"
    assert_selector ".admin-editor-header__schedule input[name=published_at]"
    assert_no_selector "header.admin-editor-header [role=menu]"
  end
end
