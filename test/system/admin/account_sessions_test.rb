require "application_system_test_case"

# Your account's Sessions card in the browser: a row's End takes the row
# away at once and hands the focus on, and "Sign out everywhere else…"
# confirms first and leaves this session alone.
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
end
