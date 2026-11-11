require "application_system_test_case"

# The bot check as a person meets it: after three wrong passwords the
# sign-in panel draws Turnstile's widget (`bot-check`), the form posts the
# widget's answer, and the server verifies it.
#
# NO CLOUDFLARE. The widget's script is never fetched: the test defines
# `window.turnstile` (STUB) in the window before the widget's element
# connects, and the controller loads no script when it is there. The window
# outlives the page, since a wrong password is a Turbo form answer and the
# reset page is reached by a Turbo visit, so the stub stands until the
# sign-in leaves for CS Studio. Its `render` writes the hidden
# `cf-turnstile-response` input the real widget writes, and counts. The
# server's siteverify is `with_bot_check`'s, and every request to
# challenges.cloudflare.com is blocked in the browser besides
# (`block_cloudflare`). The sign-in pages load the `application` entry
# point only, so a test waits for what the page shows, as
# `password_reset_test.rb` does.
class Admin::SignInBotCheckSystemTest < ApplicationSystemTestCase
  WIDGET = "[data-controller=bot-check] [data-bot-check-target=widget]".freeze
  ANSWER = "input[name='cf-turnstile-response']".freeze

  STUB = <<~JS.freeze
    window.turnstileCalls = { render: [], remove: [] }
    window.turnstile = {
      render(container, options) {
        const id = `stub-${window.turnstileCalls.render.length + 1}`
        window.turnstileCalls.render.push(options)
        const answer = document.createElement("input")
        answer.type = "hidden"
        answer.name = "cf-turnstile-response"
        answer.value = `answer-${id}`
        answer.dataset.stubWidget = id
        container.append(answer)
        return id
      },
      remove(id) {
        window.turnstileCalls.remove.push(id)
        document.querySelectorAll(`[data-stub-widget="${id}"]`).forEach((element) => element.remove())
      },
    }
  JS

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @user = users(:one)
    # "Forgot your password?" is drawn only when mail works.
    put_mail_state(:working)
  end

  def block_cloudflare = page.driver.browser.network.blocklist = [ %r{\Ahttps://challenges\.cloudflare\.com/} ]

  def renders = page.evaluate_script("window.turnstileCalls.render")

  def removes = page.evaluate_script("window.turnstileCalls.remove")

  def answers_in_page = page.evaluate_script("document.querySelectorAll(#{ANSWER.to_json}).length")

  # Everything Turbo keeps of pages that were left, as text.
  def turbo_snapshots
    page.evaluate_script("Object.values(Turbo.session.view.snapshotCache.snapshots).map((snapshot) => snapshot.element.outerHTML)")
  end

  def fail_sign_in(times)
    times.times do |index|
      fill_in "Email", with: @user.email_address
      fill_in "Password", with: "wrong-#{index}"
      press "Sign in"
      assert_selector "#alert", text: "Try another email address or password."
      # The answer is a new page: wait for it before the next try.
      assert_selector "input[name=password]" do |field|
        field.value.empty?
      end
    end
  end

  def sign_in_bot_check_server = with_bot_check(:passed, hostname: Capybara.current_session.server.host) { yield }

  test "the bot check renders once, posts its answer with the form, and is removed before Turbo caches the page" do
    sign_in_bot_check_server do
      block_cloudflare
      visit admin_sign_in_path
      assert_selector "input[name=email_address]"
      assert_no_selector "[data-controller=bot-check]"
      page.execute_script(STUB)

      fail_sign_in(3)

      assert_selector "#turnstile-hint", text: "A quick check is needed before you can sign in."
      assert_selector "#{WIDGET} #{ANSWER}", visible: :all, count: 1
      await_frames
      assert_equal 1, renders.size, "one widget per page"
      assert_equal 1, answers_in_page
      options = renders.sole
      assert_equal SignInHelper::BOT_CHECK_KEYS["TURNSTILE_SITE_KEY"], options["sitekey"]
      assert_equal SignIn::BotCheck::ACTION, options["action"]
      assert_equal "flexible", options["size"]
      assert_equal "en", options["language"]
      assert_includes %w[light dark], options["theme"]

      # Left by a Turbo visit: the widget is gone before the snapshot.
      click_on "Forgot your password?"
      assert_text "Send reset link"
      assert_equal [ "stub-1" ], removes
      snapshot = turbo_snapshots.find { |html| html.include?("turnstile-hint") }
      assert snapshot, "the sign-in page is in Turbo's snapshots"
      assert_not_includes snapshot, "cf-turnstile-response"
      assert_not_includes snapshot, "answer-stub-1"

      # Back shows the snapshot, and a fresh widget is drawn into it.
      page.go_back
      assert_selector "#{WIDGET} #{ANSWER}[value='answer-stub-2']", visible: :all, count: 1
      assert_equal 2, renders.size

      fill_in "Email", with: @user.email_address
      fill_in "Password", with: "password"
      press "Sign in"
      assert_selector "nav[aria-label='Modules']", wait: 15
      assert_equal [ "answer-stub-2" ], bot_check_requests.map { |form| form["response"] }
    end
  end

  test "a change of theme draws the widget again, in the theme chosen" do
    sign_in_bot_check_server do
      block_cloudflare
      visit admin_sign_in_path
      assert_selector "input[name=email_address]"
      page.execute_script(STUB)
      fail_sign_in(3)
      assert_selector "#{WIDGET} #{ANSWER}", visible: :all, count: 1
      before = renders.sole["theme"]
      after = before == "dark" ? "light" : "dark"

      within("[role=radiogroup][aria-label='Theme']") { press after.capitalize }

      assert_eventually(message: "the widget was not drawn again") { renders.size == 2 }
      assert_equal after, renders.last["theme"]
      assert_equal [ "stub-1" ], removes
      assert_equal 1, answers_in_page
    end
  end

  test "when Turnstile's script cannot load, the hint says so and Sign in stays" do
    sign_in_bot_check_server do
      block_cloudflare
      visit admin_sign_in_path
      fail_sign_in(3)

      assert_selector "#turnstile-hint", text: "The check couldn't load. Reload the page to try again."
      assert_no_selector ANSWER, visible: :all
      assert_selector "button[type=submit]:not([disabled])", text: "Sign in"
    end
  end
end
