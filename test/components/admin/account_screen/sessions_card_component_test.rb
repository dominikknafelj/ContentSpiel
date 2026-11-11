require "test_helper"

# Your account's Sessions card: the current session first, the others by
# when they were last seen, each said in a person's words, and the foot that
# offers to end the others only while there are others.
class Admin::AccountScreen::SessionsCardComponentTest < ViewComponent::TestCase
  FIREFOX_MAC = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7; rv:130.0) Gecko/20100101 Firefox/130.0".freeze
  CHROME_WINDOWS = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36".freeze
  FIREFOX_BSD = "Mozilla/5.0 (X11; FreeBSD amd64; rv:130.0) Gecko/20100101 Firefox/130.0".freeze

  # Noon, so "2h ago" is still today in any zone the suite runs in.
  setup do
    travel_to Time.zone.parse("2026-11-11 12:00")
    @user = users(:reader)
  end

  def start(user_agent: FIREFOX_MAC, ip_address: "192.0.2.10", seen: Time.current, method: "password")
    Session.start(user: @user, method: method, user_agent: user_agent, ip_address: ip_address, at: seen)
  end

  def card(current, sessions = @user.sessions.to_a)
    with_request_url("/cs-studio/account") do
      render_inline Admin::AccountScreen::SessionsCardComponent.new(sessions: sessions, current: current)
    end
  end

  def rows = page.all("#account-sessions li[id^='session-']").map { |row| row[:id] }

  test "the current session is first, with This session and no End, and the others follow by when they were last seen" do
    older = start(seen: 3.days.ago)
    current = start(seen: 2.hours.ago)
    newer = start(seen: 1.hour.ago)

    card(current)

    assert_selector "section#account-sessions[aria-labelledby=sessions] h2#sessions", text: "Sessions"
    assert_text "Where you're signed in. End a session you don't recognise, then change your password."
    assert_equal [ "session-#{current.id}", "session-#{newer.id}", "session-#{older.id}" ], rows
    assert_selector "#session-#{current.id}", text: "This session"
    assert_no_selector "#session-#{current.id} button"
    assert_no_selector "#session-#{newer.id}", text: "This session"
    assert_selector "#session-#{newer.id} form[action='/cs-studio/account/sessions/#{newer.id}'] input[name=_method][value=delete]", visible: :all
    assert_selector "#session-#{newer.id} button[type=submit][aria-label='End the session in Firefox on macOS']", text: "End"
  end

  test "line 2 says the address, Active now or how long ago, and how the person signed in, joined by a dot" do
    current = start(ip_address: "192.0.2.10")
    other = start(ip_address: "198.51.100.7", seen: 2.hours.ago)
    blank = start(ip_address: nil, seen: 3.hours.ago)

    card(current)

    assert_selector "#session-#{current.id} [data-session-details]", exact_text: "192.0.2.10 · Active now · Signed in with password"
    assert_selector "#session-#{other.id} [data-session-details]", exact_text: "198.51.100.7 · Active 2h ago · Signed in with password"
    assert_selector "#session-#{other.id} [data-session-details] time[datetime]"
    assert_selector "#session-#{blank.id} [data-session-details]", exact_text: "Active 3h ago · Signed in with password"
  end

  test "the device is said in the words of each of SessionDevice's four cases" do
    current = start(user_agent: FIREFOX_MAC)
    windows = start(user_agent: CHROME_WINDOWS, seen: 1.minute.ago)
    bsd = start(user_agent: FIREFOX_BSD, seen: 2.minutes.ago)
    unknown = start(user_agent: nil, seen: 3.minutes.ago)

    card(current)

    assert_selector "#session-#{current.id} [data-session-device]", exact_text: "Firefox on macOS"
    assert_selector "#session-#{windows.id} [data-session-device]", exact_text: "Chrome on Windows"
    assert_selector "#session-#{bsd.id} [data-session-device]", exact_text: "Firefox"
    assert_selector "#session-#{unknown.id} [data-session-device]", exact_text: "Unknown browser"
    assert_selector "#session-#{unknown.id} button[aria-label='End the session in Unknown browser']"

    # No real user agent reads as a system without a browser, so the device
    # is given that answer here.
    SessionDevice.define_singleton_method(:new) { |_agent| Struct.new(:key_and_values).new([ "os_only", { os: "Android" } ]) }
    begin
      card(current)
    ensure
      SessionDevice.singleton_class.remove_method(:new)
    end
    assert_selector "#session-#{windows.id} [data-session-device]", exact_text: "A browser on Android"
  end

  test "the foot counts the others and offers to end them, behind a confirm that is not destructive" do
    current = start
    2.times { |index| start(seen: (index + 1).hours.ago) }

    card(current)

    assert_selector "#account-sessions-foot", text: "2 other sessions"
    assert_selector "#account-sessions-foot button[type=button][data-admin--ui--dialog-id-param=end-other-sessions]", text: "Sign out everywhere else…"
    assert_selector "dialog#end-other-sessions", visible: :all, text: "Sign out everywhere else?"
    assert_selector "dialog#end-other-sessions p", visible: :all,
      exact_text: "Your 2 other sessions end, and those browsers must sign in again. You stay signed in here."
    assert_selector "dialog#end-other-sessions form[action='/cs-studio/account/sessions'] button[type=submit]", visible: :all, text: "Sign out everywhere else"
    assert_no_selector "dialog#end-other-sessions button[autofocus]", visible: :all
  end

  test "with one other session the foot and the dialog say one" do
    current = start
    start(seen: 1.hour.ago)

    card(current)

    assert_selector "#account-sessions-foot", text: "1 other session"
    assert_selector "dialog#end-other-sessions p", visible: :all,
      exact_text: "Your other session ends, and that browser must sign in again. You stay signed in here."
  end

  test "with no other session the foot says so and offers nothing" do
    current = start

    card(current)

    assert_equal [ "session-#{current.id}" ], rows
    assert_selector "#account-sessions-foot p", exact_text: "You're not signed in anywhere else."
    assert_no_selector "#account-sessions-foot button"
    assert_no_selector "dialog", visible: :all
  end

  test "the card holds no field of a form a save bar counts" do
    current = start
    start(seen: 1.hour.ago)

    card(current)

    assert_no_selector "#account-sessions form[data-controller*='save-bar']", visible: :all
    assert_no_selector "#account-sessions input:not([type=hidden])", visible: :all
  end
end
