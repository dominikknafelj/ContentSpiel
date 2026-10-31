require "application_system_test_case"

# The password reset as a person takes it (safe-address spec §4): the mailed
# link carries its token after a "#", which the browser sends to no server;
# the page's script (`reset-token`) moves it into the form's hidden field
# and out of the address bar; the form sends it in its body.
#
# The reset pages load the `application` entry point only (no admin
# controller), so there is nothing for `await_admin_controllers` to wait
# for: a test waits for what the script shows, the form or the message.
# The form is shown at once and is `aria-busy`, its fields read-only, until
# the script's one question to the server (is this link still good?) is
# answered: `OPEN` is the form after that, the one a person can type into.
class Admin::PasswordResetSystemTest < ApplicationSystemTestCase
  include ActionMailer::TestHelper

  NEW_PASSWORD = "a-new-long-password-1".freeze
  FORM = "form[data-reset-token-target=form]".freeze
  OPEN = "#{FORM}:not([hidden]):not([aria-busy])".freeze
  CHECK = "/cs-studio/password/check".freeze
  INCOMPLETE = "This link is incomplete. Open the link in the email again, or ask for a new one.".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @user = users(:one)
    # The request page is closed unless mail works (undone with the test).
    put_mail_state(:working)
  end

  # Asks for a reset as a person does and answers the link of the mail. The
  # job that delivers it runs in the server's thread, at once.
  def mailed_link
    visit new_admin_password_path
    fill_in "Email", with: @user.email_address
    perform_enqueued_jobs do
      press "Send reset link"
      assert_text "Check your email"
    end

    ActionMailer::Base.deliveries.last.text_part.body.to_s[%r{https?://\S+}]
  end

  def token_of(link) = link.split("#", 2).last

  def address = page.evaluate_script("window.location.href")

  def token_field = find("input[name=token]", visible: :all)

  # Every address the browser asked a server for since the page was opened.
  def requests = page.driver.browser.network.traffic.map(&:request)

  def requested_addresses = requests.map(&:url)

  def checks = requests.select { |request| URI.parse(request.url).path == CHECK }

  # A link of the mail's shape for a token made here, with no mail.
  def link_for(token) = "#{admin_edit_password_path}##{token}"

  # `window.fetch` answers the script's check as `answer` says (a JavaScript
  # expression for a promise) and hands every other request to the real one.
  # It lives as long as the window, so the page under test is then reached
  # by a Turbo visit, which keeps the window.
  def answer_checks_with(answer)
    page.execute_script(<<~JS)
      const real = window.fetch
      window.checksAsked = 0
      window.fetch = (resource, options) => {
        if (!String(resource).endsWith(#{CHECK.to_json})) return real(resource, options)
        window.checksAsked += 1
        return #{answer}
      }
    JS
  end

  # Everything Turbo keeps of pages that were left, as text.
  def turbo_snapshots
    page.evaluate_script("Object.values(Turbo.session.view.snapshotCache.snapshots).map((snapshot) => snapshot.element.outerHTML)")
  end

  test "the mailed link opens the form, the token leaves the address, and the new password signs in" do
    link = mailed_link
    token = token_of(link)
    assert_match %r{/cs-studio/password/edit#\S+\z}, link

    visit link
    assert_selector OPEN
    assert_no_text INCOMPLETE

    assert_equal link.split("#", 2).first, address, "the address bar holds neither the # nor the token"
    assert_equal token, token_field.value
    assert_equal "password", page.evaluate_script("document.activeElement.id"), "the first field has the focus once the form is shown"

    fill_in "New password", with: NEW_PASSWORD
    fill_in "Repeat new password", with: NEW_PASSWORD
    press "Set password"

    assert_text "Password has been reset."
    assert_current_path admin_sign_in_path
    requests.each do |request|
      assert_not_includes request.url, token, "the token was sent in an address"
      assert_not_includes request.headers.to_s, token, "the token was sent in a header (a Referer) of #{request.url.split("#").first}"
    end
    assert_equal [ "POST" ], checks.map(&:method), "the link was asked about once, by a POST"
    assert_includes requested_addresses.map { |url| URI.parse(url).path }, "/cs-studio/password", "the form's own request is among them"
    assert @user.reload.authenticate(NEW_PASSWORD)

    sign_in_via_form(@user, password: NEW_PASSWORD)
  end

  test "the page opened without a token says the link is incomplete and shows no form, and so does the old link" do
    visit admin_edit_password_path

    assert_selector "[role=alert]", text: INCOMPLETE
    assert_no_selector FORM
    assert_selector "#{FORM}[hidden]", visible: :all
    assert_no_field "New password"

    # The link as it was mailed before: its token is in the path, and the
    # server answers with the page and no token.
    token = @user.password_reset_token
    visit "/cs-studio/password/#{token}/edit"

    assert_selector "[role=alert]", text: INCOMPLETE
    assert_no_selector FORM
    assert_not_includes address, token
    assert_equal "", token_field.value

    press "Send a new link"
    assert_selector "h1", text: "Reset password"
  end

  # The 422: Turbo draws the answer in place, with the token in its field,
  # and the address is still the page's own.
  test "a refused password comes back on the form with the token still in it, and the second try sets it" do
    link = mailed_link
    token = token_of(link)
    visit link
    assert_selector OPEN

    fill_in "New password", with: NEW_PASSWORD
    fill_in "Repeat new password", with: "another-long-password-2"
    press "Set password"

    assert_selector "#alert[role=alert]", text: "Password confirmation doesn't match Password"
    assert_equal 1, checks.size, "the form that came back was not asked about again"
    assert_selector OPEN
    assert_no_text INCOMPLETE
    assert_equal token, token_field.value
    assert_not_includes address, token
    assert_not_includes address, "#"

    fill_in "New password", with: NEW_PASSWORD
    fill_in "Repeat new password", with: NEW_PASSWORD
    press "Set password"

    assert_text "Password has been reset."
    assert @user.reload.authenticate(NEW_PASSWORD)
  end

  # THE EARLY CHECK. A link that is no good says so before anything is
  # typed: the page is replaced by the request page's "expired" state.
  # The token is made here and time moved past its fifteen minutes BEFORE
  # the page is opened; it is the server that judges it, so the browser's
  # clock (which `travel` does not move) has no part.
  test "a lapsed link shows the expired state at once, with nothing typed, and its token is in no address" do
    token = @user.password_reset_token
    travel 16.minutes

    visit link_for(token)

    assert_selector "h1", text: "This reset link has expired"
    assert_text "This reset link has expired. Ask for a new one."
    assert_current_path new_admin_password_path(expired: 1)
    assert_no_selector FORM, visible: :all
    assert_not_includes address, token
    assert_not_includes page.evaluate_script("document.documentElement.outerHTML"), token
  end

  # Replaced, not added to the history: Back leads to where the person
  # came from, not to a form that cannot work.
  test "a tampered link shows the expired state at once too, in the place of the page: Back goes to the page before" do
    visit admin_sign_in_path
    assert_selector "h1", text: "Sign in"

    page.execute_script("Turbo.visit(#{"#{link_for(@user.password_reset_token)}tampered".to_json})")

    assert_selector "h1", text: "This reset link has expired"
    assert_no_selector FORM, visible: :all

    page.go_back
    assert_selector "h1", text: "Sign in"
  end

  # Until the answer is there the form is on screen but its fields take
  # nothing, so no password is typed into a form that is about to go.
  test "while the link is being asked about the fields are read-only, and they open when it is answered good" do
    visit admin_sign_in_path
    assert_selector "h1", text: "Sign in"
    answer_checks_with("new Promise((resolve) => { window.answerCheck = () => resolve(new Response(null, { status: 204 })) })")

    page.execute_script("Turbo.visit(#{link_for(@user.password_reset_token).to_json})")

    assert_selector "#{FORM}[aria-busy=true]:not([hidden])"
    assert_selector "#password[readonly]"
    assert_selector "#password_confirmation[readonly]"
    assert_selector "[data-password-submit][disabled]"
    assert_no_text INCOMPLETE

    page.execute_script("window.answerCheck()")

    assert_selector OPEN
    assert_no_selector "#{FORM} input[readonly]"
    assert_eventually(message: "the first field did not get the focus") { page.evaluate_script("document.activeElement.id") == "password" }
    assert_equal 1, page.evaluate_script("window.checksAsked")
  end

  # The check is advice. Where it cannot be made or says anything but "not
  # good", the form is shown and the form's own request decides.
  test "a check that fails, is refused or is limited leaves the form open, and the form still sets the password" do
    [ "Promise.reject(new TypeError('no network'))", "Promise.resolve(new Response(null, { status: 429 }))",
      "Promise.resolve(new Response(null, { status: 422 }))", "Promise.resolve(new Response(null, { status: 500 }))" ].each do |answer|
      visit admin_sign_in_path
      assert_selector "h1", text: "Sign in"
      answer_checks_with(answer)

      page.execute_script("Turbo.visit(#{link_for(@user.password_reset_token).to_json})")

      assert_selector OPEN
      assert_no_selector "#{FORM} input[readonly]"
      assert_equal 1, page.evaluate_script("window.checksAsked"), answer
    end

    fill_in "New password", with: NEW_PASSWORD
    fill_in "Repeat new password", with: NEW_PASSWORD
    press "Set password"

    assert_text "Password has been reset."
    assert @user.reload.authenticate(NEW_PASSWORD)
  end

  # And the rule is still the form's: a link that was good when the page
  # asked and is not when the form is sent gets the same expired state.
  test "a link that lapses while the password is typed is answered when the form is sent: the expired state" do
    visit link_for(@user.password_reset_token)
    assert_selector OPEN

    travel 16.minutes
    fill_in "New password", with: NEW_PASSWORD
    fill_in "Repeat new password", with: NEW_PASSWORD
    press "Set password"

    assert_selector "h1", text: "This reset link has expired"
    assert_not @user.reload.authenticate(NEW_PASSWORD)
  end

  # A page left while its check is on the way is not thrown to the expired
  # state from wherever the person has gone.
  #
  # WHAT THIS PINS: the one line of `check` that returns when the page is no
  # longer this form (`!this.element.isConnected || this.tokenTarget.value !==
  # token`). With the line taken out the test fails: the late 410 replaces
  # the sign-in page with "This reset link has expired" (seen, three runs of
  # three). It does not tell the line's two halves apart: leaving by a Turbo
  # visit disconnects the element AND empties the field
  # (`turbo:before-cache`), so either half alone passes here. The second
  # half is for a page the browser put away without disconnecting anything
  # (`pagehide`) while its check was out; no test pins that half alone.
  #
  # What would go wrong is a `location.replace`, which commits some time
  # after the script asked for it, and when the guard works nothing happens
  # at all: so there is no condition to wait for, and the test holds still
  # for as long as such a navigation takes before it looks.
  test "an answer that arrives after the page was left moves nothing" do
    visit admin_sign_in_path
    assert_selector "h1", text: "Sign in"
    answer_checks_with("new Promise((resolve) => { window.answerCheck = () => resolve(new Response(null, { status: 410 })) })")
    page.execute_script("Turbo.visit(#{link_for(@user.password_reset_token).to_json})")
    assert_selector "#{FORM}[aria-busy=true]"

    press "CONTENT·SPIEL"
    assert_selector "h1", text: "Sign in"
    page.execute_script("window.answerCheck()")
    sleep 1 # sleep: a navigation the guard failed to stop needs time to commit, and when the guard works nothing happens to wait for

    assert_no_selector "h1", text: "This reset link has expired"
    assert_selector "h1", text: "Sign in"
    assert_current_path admin_sign_in_path
    assert_equal 1, page.evaluate_script("window.checksAsked")
  end

  # Writing a hidden field's value writes its attribute, so a copy of the
  # document would hold the token: Turbo's snapshot of a page that is left,
  # which Back shows again. The script empties the field before the snapshot
  # is taken.
  test "the token does not outlive the page: not in Turbo's snapshot, and not after Back" do
    link = mailed_link
    token = token_of(link)
    visit link
    assert_selector OPEN
    assert_equal token, token_field.value
    assert_includes page.evaluate_script("document.documentElement.outerHTML"), token, "the open page does hold it: in the field"

    press "CONTENT·SPIEL"
    assert_selector "h1", text: "Sign in"

    snapshots = nil
    assert_eventually(message: "Turbo kept no snapshot of the page that was left") { (snapshots = turbo_snapshots).any? { |html| html.include?("data-reset-token-target") } }
    snapshots.each { |html| assert_not_includes html, token }

    page.go_back
    assert_selector "[role=alert]", text: INCOMPLETE
    assert_no_selector FORM
    assert_equal "", token_field.value
    assert_not_includes address, token
    assert_not_includes page.evaluate_script("document.documentElement.outerHTML"), token
  end

  # The other copy of a page: the browser's own back/forward cache, which
  # restores a document as it was put away and connects nothing again. The
  # script empties the field and switches to the message at `pagehide`. A
  # real round trip through that cache is not to be had in this browser, so
  # the event is dispatched as the browser does for a page it keeps.
  test "a page the browser puts away keeps no token: the field is emptied and the message shown at pagehide" do
    link = mailed_link
    token = token_of(link)
    visit link
    assert_selector OPEN
    assert_equal token, token_field.value

    page.execute_script("window.dispatchEvent(new PageTransitionEvent('pagehide', { persisted: true }))")

    assert_equal "", token_field.value
    assert_not_includes page.evaluate_script("document.documentElement.outerHTML"), token
    assert_selector "#{FORM}[hidden]", visible: :all
    assert_selector "[role=alert]", text: INCOMPLETE
  end
end
