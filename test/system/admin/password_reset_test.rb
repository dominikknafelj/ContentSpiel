require "application_system_test_case"

# The password reset as a person takes it (safe-address spec §4): the mailed
# link carries its token after a "#", which the browser sends to no server;
# the page's script (`reset-token`) moves it into the form's hidden field
# and out of the address bar; the form sends it in its body.
#
# The reset pages load the `application` entry point only (no admin
# controller), so there is nothing for `await_admin_controllers` to wait
# for: a test waits for what the script shows, the form or the message.
class Admin::PasswordResetSystemTest < ApplicationSystemTestCase
  include ActionMailer::TestHelper

  NEW_PASSWORD = "a-new-long-password-1".freeze
  FORM = "form[data-reset-token-target=form]".freeze
  INCOMPLETE = "This link is incomplete. Open the link in the email again, or ask for a new one.".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @user = users(:one)
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
  def requested_addresses = page.driver.browser.network.traffic.map { |exchange| exchange.request.url }

  # Everything Turbo keeps of pages that were left, as text.
  def turbo_snapshots
    page.evaluate_script("Object.values(Turbo.session.view.snapshotCache.snapshots).map((snapshot) => snapshot.element.outerHTML)")
  end

  test "the mailed link opens the form, the token leaves the address, and the new password signs in" do
    link = mailed_link
    token = token_of(link)
    assert_match %r{/cs-studio/password/edit#\S+\z}, link

    visit link
    assert_selector "#{FORM}:not([hidden])"
    assert_no_text INCOMPLETE

    assert_equal link.split("#", 2).first, address, "the address bar holds neither the # nor the token"
    assert_equal token, token_field.value
    assert_equal "password", page.evaluate_script("document.activeElement.id"), "the first field has the focus once the form is shown"

    fill_in "New password", with: NEW_PASSWORD
    fill_in "Repeat new password", with: NEW_PASSWORD
    press "Set password"

    assert_text "Password has been reset."
    assert_current_path admin_sign_in_path
    requested_addresses.each { |url| assert_not_includes url, token, "the token was sent in an address" }
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
    assert_selector "#{FORM}:not([hidden])"

    fill_in "New password", with: NEW_PASSWORD
    fill_in "Repeat new password", with: "another-long-password-2"
    press "Set password"

    assert_selector "#alert[role=alert]", text: "Password confirmation doesn't match Password"
    assert_selector "#{FORM}:not([hidden])"
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

  test "a link whose token is not good is answered when the form is sent: the expired state" do
    link = mailed_link
    visit "#{link}tampered"
    assert_selector "#{FORM}:not([hidden])"

    fill_in "New password", with: NEW_PASSWORD
    fill_in "Repeat new password", with: NEW_PASSWORD
    press "Set password"

    assert_selector "h1", text: "This link has expired"
    assert_not @user.reload.authenticate(NEW_PASSWORD)
  end

  # Writing a hidden field's value writes its attribute, so a copy of the
  # document would hold the token: Turbo's snapshot of a page that is left,
  # which Back shows again. The script empties the field before the snapshot
  # is taken.
  test "the token does not outlive the page: not in Turbo's snapshot, and not after Back" do
    link = mailed_link
    token = token_of(link)
    visit link
    assert_selector "#{FORM}:not([hidden])"
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
end
