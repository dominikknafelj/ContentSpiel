require "application_system_test_case"

class SetupWizardTest < ApplicationSystemTestCase
  setup do
    User.destroy_all
    site_settings(:default).update!(setup_completed_at: nil)
    SetupController::RATE_LIMIT_STORE.clear
  end

  test "a fresh install goes from the token to a live homepage" do
    visit "/"
    assert_current_path "/setup/token"

    assert_selector "h1", text: "Enter your setup token"
    fill_in "Setup token", with: Setup::Token.value
    press "Continue"

    assert_text "File storage"
    assert_selector "h1", text: "System check"
    press "Continue"

    assert_selector "h1", text: "Create the admin account"
    fill_in "Email address", with: "owner@example.com"
    fill_in "Password", with: "password123"
    fill_in "Confirm password", with: "password123"
    press "Create account"

    assert_selector "h1", text: "Site identity"
    fill_in "Site title", with: "Dana's Notes"
    press "Save and continue"

    assert_selector "h1", text: "Languages"
    select "Deutsch", from: "Default language"
    press "Save and continue"

    assert_selector "h1", text: "MCP token"
    press "Generate token"

    assert_selector "h1", text: "Your MCP token"
    assert_selector "#mcp-token", text: /\A.+\z/
    press "Continue"

    assert_selector "h1", text: "Starter content"
    press "Add starter content"

    assert_selector "h1", text: "Review"
    assert_text "Blog, Resume and Now pages"
    press "Finish setup"

    assert_current_path %r{\A/avo}
    visit "/"
    assert_text "Welcome to your new site"
  end

  private

  # Clicks through JavaScript (`element.click()`) instead of a native
  # WebDriver click. On a loaded machine headless Chrome intermittently drops
  # native clicks made right after a page load -- no event reaches the
  # document and no request is sent (investigated at length on the
  # editor-experience branch: not overlays, fonts, paint holding or timer
  # throttling). A scripted click still goes through Turbo's link and form
  # handling, so this test keeps covering what it's for, e.g. that the MCP
  # token form opts out of Turbo and actually submits.
  def press(label)
    find(:link_or_button, label).execute_script("this.click()")
  end
end
