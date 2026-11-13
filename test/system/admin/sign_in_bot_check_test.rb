require "application_system_test_case"

# The bot check as a person meets it: after three wrong passwords the
# sign-in panel draws Turnstile's widget (`bot-check`), the form posts the
# widget's answer, and the server verifies it.
#
# NO CLOUDFLARE. The widget's script is never fetched: STUB is run in every
# document before the page's own scripts (`evaluate_on_new_document`), so
# `window.turnstile` is there when the widget's element connects and the
# controller loads no script. On a site with the keys the sign-in page is
# always a whole document (`Admin::SessionsController`, "THE POLICY BELONGS
# TO THE DOCUMENT"), which is why the stub must outlive a load. Its
# `render` draws what the real widget draws: an iframe from
# challenges.cloudflare.com and the hidden `cf-turnstile-response` input.
# The browser still checks the frame against the document's policy (a
# refusal is a `securitypolicyviolation`, which STUB records), and only
# then is the request itself blocked (`block_cloudflare`), as is every
# other request to Cloudflare. The server's siteverify is `with_bot_check`'s.
# The sign-in pages load the `application` entry point only, so a test
# waits for what the page shows, as `password_reset_test.rb` does.
class Admin::SignInBotCheckSystemTest < ApplicationSystemTestCase
  WIDGET = "[data-controller=bot-check] [data-bot-check-target=widget]".freeze
  ANSWER = "input[name='cf-turnstile-response']".freeze
  HINT = "A quick check is needed before you can sign in.".freeze
  UNAVAILABLE = "The check couldn't load. Reload the page to try again.".freeze

  STUB = <<~JS.freeze
    window.cspViolations = []
    document.addEventListener("securitypolicyviolation", (event) => {
      window.cspViolations.push(`${event.violatedDirective} ${event.blockedURI}`)
    })
    const documentId = Math.random().toString(36).slice(2)
    window.turnstileCalls = { render: [], remove: [] }
    window.turnstile = {
      render(container, options) {
        const id = `stub-${window.turnstileCalls.render.length + 1}`
        window.turnstileCalls.render.push(options)
        const frame = document.createElement("iframe")
        frame.src = "https://challenges.cloudflare.com/cdn-cgi/challenge-platform/stub"
        frame.dataset.stubWidget = id
        const answer = document.createElement("input")
        answer.type = "hidden"
        answer.name = "cf-turnstile-response"
        answer.value = `answer-${documentId}-${id}`
        answer.dataset.stubWidget = id
        container.append(frame, answer)
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

  def stub_turnstile = page.driver.browser.evaluate_on_new_document(STUB)

  def renders = page.evaluate_script("window.turnstileCalls.render")

  def removes = page.evaluate_script("window.turnstileCalls.remove")

  def answers_in_page = page.evaluate_script("document.querySelectorAll(#{ANSWER.to_json}).length")

  def answer_value = find(ANSWER, visible: :all).value

  # A mark on the window: gone after a whole load, kept by a Turbo visit.
  def mark_document = page.execute_script("window.sameDocument = true")

  def same_document? = page.evaluate_script("window.sameDocument === true")

  # Everything Turbo keeps of pages that were left, as text.
  def turbo_snapshots
    page.evaluate_script("Object.values(Turbo.session.view.snapshotCache.snapshots).map((snapshot) => snapshot.element.outerHTML)")
  end

  def sign_in_snapshot = turbo_snapshots.find { |html| html.include?("turnstile-hint") }

  def fail_sign_in(times)
    times.times do |index|
      fill_in "Email", with: @user.email_address
      fill_in "Password", with: "wrong-#{index}"
      press "Sign in"
      assert_selector "#alert", text: "Try another email address or password."
      # The answer is a new page: wait for it before the next try.
      assert_selector("input[name=password]") { |field| field.value.empty? }
    end
  end

  def with_keys(&block) = with_bot_check(:passed, hostname: Capybara.current_session.server.host, &block)

  test "the bot check renders once, posts its answer with the form, and is removed before Turbo caches the page" do
    with_keys do
      block_cloudflare
      stub_turnstile
      visit admin_sign_in_path
      assert_selector "input[name=email_address]"
      assert_no_selector "[data-controller=bot-check]"

      fail_sign_in(3)

      assert_selector "#turnstile-hint", text: HINT
      assert_selector "#{WIDGET} #{ANSWER}", visible: :all, count: 1
      assert_selector "#{WIDGET} iframe[src^='https://challenges.cloudflare.com/']", count: 1
      await_frames
      assert_equal 1, renders.size, "one widget per page"
      assert_equal 1, answers_in_page
      assert_empty page.evaluate_script("window.cspViolations"), "the document's policy lets Cloudflare's frame in"
      options = renders.sole
      assert_equal SignInHelper::BOT_CHECK_KEYS["TURNSTILE_SITE_KEY"], options["sitekey"]
      assert_equal SignIn::Protection::BotCheck::ACTION, options["action"]
      assert_equal "flexible", options["size"]
      assert_equal "en", options["language"]
      assert_includes %w[light dark], options["theme"]
      first_answer = answer_value

      # Left by a Turbo visit: the widget is gone before the snapshot.
      click_on "Forgot your password?"
      assert_text "Send reset link"
      assert_equal [ "stub-1" ], removes
      assert sign_in_snapshot, "the sign-in page is in Turbo's snapshots"
      assert_not_includes sign_in_snapshot, "cf-turnstile-response"
      assert_not_includes sign_in_snapshot, "challenges.cloudflare.com"
      assert_not_includes sign_in_snapshot, first_answer

      # Back is a whole load of the sign-in page, never its snapshot, and
      # it draws a fresh widget.
      mark_document
      page.go_back
      assert_selector "#{WIDGET} #{ANSWER}", visible: :all, count: 1
      assert_not same_document?, "Back to the sign-in page loads it whole"
      assert_equal 1, renders.size
      assert_empty page.evaluate_script("window.cspViolations")
      answer = answer_value
      assert_not_equal first_answer, answer

      fill_in "Email", with: @user.email_address
      fill_in "Password", with: "password"
      press "Sign in"
      assert_selector "nav[aria-label='Modules']", wait: 15
      assert_equal [ answer ], bot_check_requests.map { |form| form["response"] }
    end
  end

  # The reset pages share sign-in's layout and scripts, so Turbo would keep
  # the document across the visit; with the keys the sign-in page refuses
  # that, without them it is an ordinary Turbo visit.
  test "arriving at sign-in by Turbo from a signed-out page loads it whole when the site has the keys" do
    visit new_admin_password_path
    assert_text "Send reset link"
    mark_document
    find("header a", text: "CONTENT·SPIEL").click
    assert_selector "input[name=email_address]"
    assert same_document?, "without the keys the visit is Turbo's, in the same document"

    with_keys do
      visit new_admin_password_path
      assert_text "Send reset link"
      mark_document
      find("header a", text: "CONTENT·SPIEL").click
      assert_selector "input[name=email_address]"
      assert_eventually(message: "the sign-in page was drawn into the reset page's document") { !same_document? }
    end
  end

  test "a change of theme draws the widget again, in the theme chosen" do
    with_keys do
      block_cloudflare
      stub_turnstile
      visit admin_sign_in_path
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

  test "when Turnstile's script cannot load, the hint says so, Sign in stays, and the snapshot keeps the server's hint" do
    with_keys do
      block_cloudflare
      visit admin_sign_in_path
      fail_sign_in(3)

      assert_selector "#turnstile-hint", text: UNAVAILABLE
      assert_no_selector ANSWER, visible: :all
      assert_selector "button[type=submit]:not([disabled])", text: "Sign in"

      click_on "Forgot your password?"
      assert_text "Send reset link"
      assert sign_in_snapshot, "the sign-in page is in Turbo's snapshots"
      assert_equal HINT, Nokogiri::HTML(sign_in_snapshot).at_css("#turnstile-hint").text
    end
  end
end
