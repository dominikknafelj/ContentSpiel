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

    # The answer to this press is the slowest of the wizard: the POST is
    # `StarterContents::Add`, the same service as CS Studio's "Create starter
    # pages" (three pages, their posts and blocks and every derived row: 639
    # statements, about a second cold on an idle laptop), and only then the
    # redirect to this step. On a two-core runner that is more than
    # Capybara's default 2 s, and nothing was wrong: the failed run still
    # showed "Starter content" as the heading (the same failure comes from
    # delaying the service by 2.5 s). So this one assertion waits longer,
    # as the one after "Create starter pages" does
    # (test/system/admin/tokens_related_posts_and_starter_pages_test.rb).
    assert_selector "h1", text: "Review", wait: 10
    assert_text "Blog, Resume and Now pages"
    assert_text "claude-desktop (created)"
    press "Finish setup"

    # The press's own answer is short (`StarterContents::EnsureHome` and
    # `Setup.complete!`, 11 statements, since the home page is there by
    # now), but it redirects to CS Studio's dashboard, which this server
    # draws here for the first time: its queries, every component of the
    # shell and the admin scripts, all cold. A tenth of a second on an idle
    # laptop and nobody has measured it on a two-core runner, where the run
    # that failed stopped one press earlier. The same wait as above, so the
    # next run does not find out. The wizard's other presses answer with 9
    # to 25 statements and a page of the wizard, and keep the default.
    assert_current_path %r{\A/cs-studio}, wait: 10
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
