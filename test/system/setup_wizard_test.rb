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

    fill_in "Setup token", with: Setup::Token.value
    click_on "Continue"

    assert_text "File storage"
    click_on "Continue"

    fill_in "Email address", with: "owner@example.com"
    fill_in "Password", with: "password123"
    fill_in "Confirm password", with: "password123"
    click_on "Create account"

    fill_in "Site title", with: "Dana's Notes"
    click_on "Save and continue"

    choose "Deutsch"
    click_on "Save and continue"

    click_on "Skip"                  # MCP token
    click_on "Add starter content"

    assert_text "Blog, Resume and Now pages"
    click_on "Finish setup"

    assert_current_path %r{\A/avo}
    visit "/"
    assert_text "Welcome to your new site"
  end
end
