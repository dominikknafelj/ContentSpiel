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
    press "Continue"

    assert_selector "h1", text: "Site identity"
    fill_in "Site title", with: "Dana's Notes"
    # The logo's drop zone works on setup, which loads only the `application`
    # JS entry: attaching through "Choose file" echoes the chosen name.
    attach_file("site_setting_logo", file_fixture("tiny.png").to_s, visible: :all)
    assert_selector "[data-file-drop-target=name]", text: "tiny.png"
    press "Continue"

    assert_selector "h1", text: "Languages"
    select "Deutsch", from: "Default language"
    press "Continue"

    assert_selector "h1", text: "Connect an AI agent"
    fill_in "Token name", with: "claude-desktop"
    press "Generate token"

    assert_selector "h1", text: "Your token"
    assert_selector "#mcp-token", text: /\A.+\z/
    press "Continue"

    assert_selector "h1", text: "Starter content"
    press "Add starter content"

    assert_selector "h1", text: "Review"
    assert_text "Blog, Resume and Now pages"
    assert_text "claude-desktop (created)"
    press "Finish setup"

    assert_current_path %r{\A/cs-studio}
    visit "/"
    assert_text "Welcome to your new site"
  end

  test "the admin step holds Continue back until the password is long enough" do
    visit "/setup/token"
    fill_in "Setup token", with: Setup::Token.value
    press "Continue"
    assert_selector "h1", text: "System check"
    press "Continue"
    assert_selector "h1", text: "Create the admin account"

    fill_in "Email address", with: "owner@example.com"
    fill_in "Password", with: "12345678"
    assert_text "Too short. Use 12 or more characters."
    assert_selector "button[data-password-submit][disabled]", text: "Continue"

    fill_in "Password", with: "12345678901234"
    assert_selector "button[data-password-submit]:not([disabled])", text: "Continue"
  end

  # `press` (a scripted click -- see its own comment) moved to
  # `ApplicationSystemTestCase` in cs-studio Task 9, shared by every system
  # test that needs it, this one included.
end
