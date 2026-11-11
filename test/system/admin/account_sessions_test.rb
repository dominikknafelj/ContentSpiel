require "application_system_test_case"

# Your account's Sessions card in the browser: a row's End takes the row
# away at once and hands the focus on, and "Sign out everywhere else…"
# confirms first and leaves this session alone. Neither throws away what the
# Profile and Notes form holds unsaved: a row's End is a stream that keeps
# the form, and "Sign out everywhere else…", whose redirect draws the screen
# again, waits for it.
class Admin::AccountSessionsSystemTest < ApplicationSystemTestCase
  FIREFOX_MAC = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7; rv:130.0) Gecko/20100101 Firefox/130.0".freeze
  CHROME_WINDOWS = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @user = users(:one)
    sign_in_via_form(@user)
    @newer = Session.start(user: @user, method: "password", user_agent: FIREFOX_MAC, ip_address: "192.0.2.10", at: 1.hour.ago)
    @older = Session.start(user: @user, method: "password", user_agent: CHROME_WINDOWS, ip_address: "198.51.100.7", at: 2.hours.ago)
  end

  def focused?(selector) = page.evaluate_script("document.activeElement === document.querySelector(#{selector.to_json})")

  test "End takes the row away, says Session ended. and puts the focus on the next row's End" do
    visit_screen admin_account_path

    within("#account-sessions") { assert_text "2 other sessions" }
    within("#session-#{@newer.id}") { press "End" }

    assert_no_selector "#session-#{@newer.id}"
    assert_selector "#toasts", text: "Session ended."
    within("#account-sessions") { assert_text "1 other session" }
    assert_eventually(message: "the focus is not on the next row's End") { focused?("#session-#{@older.id} button") }
    assert_not Session.exists?(@newer.id)
  end

  test "the last row's End hands the focus to Sign out everywhere else…, and with no other session left to the foot" do
    visit_screen admin_account_path

    within("#session-#{@older.id}") { press "End" }
    assert_no_selector "#session-#{@older.id}"
    assert_eventually(message: "the focus is not on the foot's button") { focused?("#account-sessions-foot button") }

    within("#session-#{@newer.id}") { press "End" }
    assert_no_selector "#session-#{@newer.id}"
    within("#account-sessions") { assert_text "You're not signed in anywhere else." }
    assert_eventually(message: "the focus is not on the foot") { focused?("#account-sessions-foot") }
  end

  test "Sign out everywhere else… confirms, then only This session is left" do
    visit_screen admin_account_path

    press "Sign out everywhere else…"
    within("dialog#end-other-sessions") do
      assert_text "Your 2 other sessions end, and those browsers must sign in again. You stay signed in here."
      press "Sign out everywhere else"
    end

    within("#account-sessions") do
      assert_text "You're not signed in anywhere else."
      assert_selector "li[id^='session-']", count: 1
      assert_selector "li[id^='session-']", text: "This session"
    end
    assert_selector "#toasts", text: "Signed out of 2 other sessions."
    assert_equal [ @user.sessions.sole.id ], @user.sessions.pluck(:id)
    assert_not Session.exists?(@newer.id)
  end

  test "Sign out everywhere else… is locked while the name is unsaved, and unlocks when it is saved" do
    visit_screen admin_account_path

    original = find_field("Your name").value
    fill_in "Your name", with: "Not Saved Yet"
    within("#account-sessions-foot") do
      assert_selector "button[disabled]", text: "Sign out everywhere else…"
      assert_text "Save or discard your changes first."
    end
    assert_no_selector "dialog#end-other-sessions[open]"

    fill_in "Your name", with: original
    within("#account-sessions-foot") do
      assert_selector "button:not([disabled])", text: "Sign out everywhere else…"
      assert_no_text "Save or discard your changes first."
    end

    fill_in "Your name", with: "Saved First"
    within("#account-sessions-foot") { assert_selector "button[disabled]", text: "Sign out everywhere else…" }
    within("#profile-form") { press "Save changes" }
    assert_selector "#toasts", text: "Settings saved"
    within("#account-sessions-foot") { assert_selector "button:not([disabled])", text: "Sign out everywhere else…" }

    press "Sign out everywhere else…"
    within("dialog#end-other-sessions") { press "Sign out everywhere else" }
    within("#account-sessions") { assert_text "You're not signed in anywhere else." }
    assert_equal "Saved First", @user.reload.name
    assert_equal 1, @user.sessions.count
  end

  test "a row's End with the name unsaved asks nothing and keeps the form's changes and its mark" do
    visit_screen admin_account_path

    fill_in "Your name", with: "Typed, Not Saved"
    assert_selector "#profile-form .admin-save-bar", text: "1 unsaved change"

    within("#session-#{@newer.id}") { press "End" }

    assert_no_selector "#session-#{@newer.id}"
    assert_selector "#toasts", text: "Session ended."
    assert_no_selector "dialog#leave-dialog[open]"
    assert_equal "Typed, Not Saved", find_field("Your name").value
    assert_selector "#profile-form .admin-save-bar", text: "1 unsaved change"
    assert_selector "#profile-form [data-admin--saving--save-bar-target=dot]:not([hidden])", visible: :all
    # The foot drawn again by the answer is locked from the start.
    within("#account-sessions-foot") { assert_selector "button[disabled]", text: "Sign out everywhere else…" }
    assert_not Session.exists?(@newer.id)
  end
end
