require "application_system_test_case"
require "support/held_test_mail"

class SetupWizardTest < ApplicationSystemTestCase
  include HeldTestMail

  setup do
    # `delete_all`, not `destroy_all`: see `SetupTestHelper#start_fresh_
    # install`'s own comment (`User#ensure_not_last_owner`).
    User.delete_all
    site_settings(:default).update!(setup_completed_at: nil)
    SetupController::RATE_LIMIT_STORE.clear
  end

  # At `localhost`, with Chrome's virtual authenticator, so the passkey step
  # adds a real passkey (an IP address has no relying party).
  test "a fresh install goes from the token to a live homepage" do
    with_virtual_authenticator { walk_from_the_token_to_a_live_homepage }
  end

  # A founding owner the policy covers, in a browser that can make no
  # passkey: the step says so in words, offers no Skip, and Enter in the
  # Name field says nothing failed. At `localhost`, where a passkey could be
  # made by another browser.
  test "a covered founding owner in a browser without passkeys is told to open the wizard in one that has them" do
    site_settings(:default).update!(passkey_policy: "owners_and_admins")
    script = page.driver.browser.page.command("Page.addScriptToEvaluateOnNewDocument", source: "delete window.PublicKeyCredential")
    on_localhost do
      visit "/setup/token"
      fill_in "Setup token", with: Setup::Token.value
      press "Continue"
      assert_selector "h1", text: "System check"
      press "Continue"
      fill_in "Email address", with: "owner@example.com"
      fill_in "Password", with: "password12345"
      fill_in "Confirm password", with: "password12345"
      press "Continue"

      assert_selector "h1", text: "Add a passkey"
      assert_text I18n.t("setup.passkey.unsupported")
      assert_selector "#setup-passkey button[type=submit]", visible: :hidden
      assert_no_link "Skip for now"

      fill_in "Name", with: "This browser"
      find_field("Name").send_keys(:enter)
      await_frames
      assert_no_text I18n.t("setup.passkey.failed")
      assert page.evaluate_script("document.getElementById('setup-passkey-name-error').textContent === ''"), "Enter said something failed"

      visit "/setup/site"
      assert_selector "h1", text: "Add a passkey"
      assert_current_path "/setup/passkey"
    end
  ensure
    page.driver.browser.page.command("Page.removeScriptToEvaluateOnNewDocument", identifier: script["identifier"]) if script
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

  test "Where do I find the log? opens the commands under the field and keeps the focus" do
    visit "/setup/token"
    assert_selector "h1", text: "Let's set up your site"
    assert_no_text "docker compose logs web"

    find("summary", text: "Where do I find the log?").click

    assert_selector "details[open]", text: "The setup token is printed in the server's log when CS Studio starts, unless you set it yourself with SETUP_TOKEN."
    assert_selector "details[open] code", text: "docker compose logs web"
    assert_selector "details[open] code", text: "kamal app logs"
    assert_selector "details[open] code", text: "contentspiel dev"
    assert_equal "Where do I find the log?", page.evaluate_script("document.activeElement.textContent").strip
    assert page.evaluate_script(<<~JS), "the disclosure stands under the field, above Continue"
      (() => {
        const field = document.getElementById("token")
        const details = document.querySelector("details")
        const button = [...document.querySelectorAll("button")].find((b) => b.textContent.trim() === "Continue")
        return Boolean(field.compareDocumentPosition(details) & Node.DOCUMENT_POSITION_FOLLOWING) &&
          Boolean(details.compareDocumentPosition(button) & Node.DOCUMENT_POSITION_FOLLOWING)
      })()
    JS
  end

  test "the Mail step's security switch sets the port unless another port was typed" do
    visit "/setup/token"
    fill_in "Setup token", with: Setup::Token.value
    press "Continue"
    assert_selector "h1", text: "System check"
    press "Continue"
    fill_in "Email address", with: "owner@example.com"
    fill_in "Password", with: "password12345"
    fill_in "Confirm password", with: "password12345"
    press "Continue"
    # At Capybara's 127.0.0.1 no passkey can be made: the step says so.
    assert_selector "h1", text: "Add a passkey"
    click_link "Continue"
    assert_selector "h1", text: "Site identity"
    fill_in "Site title", with: "Dana's Notes"
    press "Continue"
    assert_selector "h1", text: "Mail"
    assert_field "Port", with: "587"

    find("label", exact_text: "TLS").click
    assert_field "Port", with: "465"
    find("label", exact_text: "STARTTLS").click
    assert_field "Port", with: "587"

    fill_in "Port", with: "2525"
    find("label", exact_text: "TLS").click
    assert_field "Port", with: "2525"
  end

  # The row puts Send test mail first and Continue last; the form's first
  # submit button is a hidden Continue, so Enter in any field continues.
  test "Enter in a Mail field continues and sends no mail, whatever the row's order" do
    visit "/setup/token"
    fill_in "Setup token", with: Setup::Token.value
    press "Continue"
    assert_selector "h1", text: "System check"
    press "Continue"
    fill_in "Email address", with: "owner@example.com"
    fill_in "Password", with: "password12345"
    fill_in "Confirm password", with: "password12345"
    press "Continue"
    # At Capybara's 127.0.0.1 no passkey can be made: the step says so.
    assert_selector "h1", text: "Add a passkey"
    click_link "Continue"
    assert_selector "h1", text: "Site identity"
    fill_in "Site title", with: "Dana's Notes"
    press "Continue"
    assert_selector "h1", text: "Mail"
    ActionMailer::Base.deliveries.clear

    assert_equal "Send test mail", find("#setup-mail-actions").all("button, a").first.text.strip
    fill_in "Server", with: "smtp.enter.test"
    fill_in "Sender address", with: "hello@site.test"
    find_field("Sender address").send_keys(:enter)

    assert_selector "h1", text: "Languages"
    assert_empty ActionMailer::Base.deliveries
    assert_equal "smtp.enter.test", SiteSetting.instance.mail_server
  end

  test "Send test mail shows it is working and a second press while waiting sends nothing" do
    visit "/setup/token"
    fill_in "Setup token", with: Setup::Token.value
    press "Continue"
    assert_selector "h1", text: "System check"
    press "Continue"
    fill_in "Email address", with: "owner@example.com"
    fill_in "Password", with: "password12345"
    fill_in "Confirm password", with: "password12345"
    press "Continue"
    # At Capybara's 127.0.0.1 no passkey can be made: the step says so.
    assert_selector "h1", text: "Add a passkey"
    click_link "Continue"
    assert_selector "h1", text: "Site identity"
    fill_in "Site title", with: "Dana's Notes"
    press "Continue"
    assert_selector "h1", text: "Mail"
    fill_in "Sender address", with: "hello@site.test"
    MailTestLimit.store.clear

    with_held_test_mail do |entered, release, calls|
      press "Send test mail"
      entered.pop
      assert_selector "button[disabled]", text: "Sending…"
      assert_equal 1, calls.value
      find("button[name=send_test]").click # a native click on the disabled button: nothing is sent
      await_frames
      assert_equal 1, calls.value
      release << true
      assert_selector "#setup-mail-test [role=status]", text: "Test mail sent to owner@example.com"
      assert_equal 1, calls.value
    end
  end

  private

  def walk_from_the_token_to_a_live_homepage
    visit "/"
    assert_current_path "/setup/token"

    assert_text "Welcome to Content·Spiel"
    assert_selector "h1", text: "Let's set up your site"
    assert_text "Step 1 of 10"
    within("nav[aria-label='Setup steps']") do
      assert_selector "li", text: /System check\s*Optional\z/
      assert_no_text "OPTIONAL"
    end
    fill_in "Setup token", with: Setup::Token.value
    press "Continue"

    assert_text "Step 2 of 10"
    assert_text "File storage"
    assert_selector "h1", text: "System check"
    press "Continue"

    assert_selector "h1", text: "Create the admin account"
    fill_in "Email address", with: "owner@example.com"
    fill_in "Password", with: "password12345"
    fill_in "Confirm password", with: "password12345"
    press "Continue"

    # The passkey step: optional under the test environment's policy
    # (nobody), and taken here. Add passkey with no name says so; with one,
    # the browser's prompt answers at once, the codes stand in place of the
    # step, and Done goes on.
    assert_selector "h1", text: "Add a passkey"
    assert_link "Skip for now"
    add = find("#setup-passkey button[type=submit]", text: "Add passkey")
    add.click
    assert_selector "#setup-passkey [role=alert]", text: "Give the passkey a name."
    fill_in "Name", with: "This browser"
    add.click
    assert_selector "#setup-passkey h1", text: "Save your recovery codes"
    codes = find("#setup-passkey [data-admin--ui--recovery-codes-target=list]", visible: :all).text(:all).split
    assert_equal RecoveryCode::COUNT, codes.size
    assert_equal [ "This browser" ], User.sole.passkeys.pluck(:name)
    check "I have saved these codes"
    press "Done"

    assert_selector "h1", text: "Site identity"
    assert_not_includes page.html, codes.first, "no code is left in the page"
    fill_in "Site title", with: "Dana's Notes"
    # The logo's drop zone works on setup, which loads only the `application`
    # JS entry: attaching through "Choose file" echoes the chosen name.
    attach_file("site_setting_logo", file_fixture("tiny.png").to_s, visible: :all)
    assert_selector "[data-file-drop-target=name]", text: "tiny.png"
    press "Continue"

    # The optional Mail step is skipped; the review says so.
    assert_selector "h1", text: "Mail"
    click_link "Skip for now"

    assert_selector "h1", text: "Languages"
    select "Deutsch", from: "Default language"
    press "Continue"

    assert_selector "h1", text: "Connect an AI agent"
    fill_in "Token name", with: "claude-desktop"
    press "Generate token"

    assert_selector "h1", text: "Your token"
    assert_selector "#mcp-token", text: /\A.+\z/
    # The reveal is the AI assistant page's: Copy copies the box's text, and
    # `pagehide` blanks it. No line here prints the token: each check is a
    # yes or no with its own words.
    await_admin_controllers
    page.execute_script("window.__copied = null; Object.defineProperty(navigator, 'clipboard', { value: { writeText: (text) => { window.__copied = text; return Promise.resolve() } }, configurable: true })")
    press "Copy"
    assert_selector "button", text: "Copied"
    assert page.evaluate_script("window.__copied === document.getElementById('mcp-token').textContent && window.__copied.length > 0"), "Copy did not copy the box's text"
    page.execute_script("window.__copied = null; window.dispatchEvent(new PageTransitionEvent('pagehide', { persisted: true }))")
    assert page.evaluate_script("document.getElementById('mcp-token').textContent === ''"), "the token was not blanked at pagehide"
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
    assert_text "Not set up. Password resets and invites stay off until mail works."
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
end
