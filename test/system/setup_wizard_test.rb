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
    click_on "Continue"

    assert_text "File storage"
    assert_selector "h1", text: "System check"
    click_on "Continue"

    assert_selector "h1", text: "Create the admin account"
    fill_in "Email address", with: "owner@example.com"
    fill_in "Password", with: "password123"
    fill_in "Confirm password", with: "password123"
    click_on "Create account"

    assert_selector "h1", text: "Site identity"
    fill_in "Site title", with: "Dana's Notes"
    click_on "Save and continue"

    assert_selector "h1", text: "Languages"
    choose "Deutsch"
    click_on "Save and continue"

    assert_selector "h1", text: "MCP token"
    click_on "Generate token"

    assert_selector "h1", text: "Your MCP token"
    assert_selector "#mcp-token", text: /\A.+\z/
    click_on "Continue"

    assert_selector "h1", text: "Starter content"
    click_on "Add starter content"

    assert_selector "h1", text: "Review"
    assert_text "Blog, Resume and Now pages"
    click_on "Finish setup"

    assert_current_path %r{\A/avo}
    visit "/"
    assert_text "Welcome to your new site"
  end
end
