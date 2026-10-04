require "application_system_test_case"

class SetupWizardTest < ApplicationSystemTestCase
  setup do
    # `delete_all`, not `destroy_all` -- see `SetupTestHelper#start_fresh_
    # install`'s own comment (Task 8's `User#ensure_not_last_owner`).
    User.delete_all
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
    fill_in "Password", with: "password12345"
    fill_in "Confirm password", with: "password12345"
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

    assert_current_path %r{\A/cs-studio}
    visit "/"
    assert_text "Welcome to your new site"
  end

  # `press` (a scripted click -- see its own comment) moved to
  # `ApplicationSystemTestCase` in cs-studio Task 9, shared by every system
  # test that needs it, this one included.
end
