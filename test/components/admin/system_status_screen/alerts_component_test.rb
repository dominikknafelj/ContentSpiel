require "test_helper"

# `Admin::SystemStatusScreen::AlertsComponent` and its rows: the System status
# card of recent alerts.
class Admin::SystemStatusScreen::AlertsComponentTest < ViewComponent::TestCase
  setup { Current.actor = users(:one) }
  teardown { Current.reset }

  def alert(kind:, details:, occurrences: 1, last_seen_at: 1.hour.ago, mailed_at: nil)
    Alerts::Alert.new(kind: kind, fingerprint: SecureRandom.hex(8), details: details, occurrences: occurrences,
      first_seen_at: last_seen_at, last_seen_at: last_seen_at, mailed_at: mailed_at)
  end

  def error(**options) = alert(kind: "error", details: { "error_class" => "RuntimeError", "place" => "app/models/page.rb:120" }, **options)

  def security(**options) = alert(kind: "sign_in_failures", details: { "failed" => 21, "locked" => 0 }, occurrences: 12, **options)

  AUDIT = "/cs-studio/audit_events".freeze

  def card(alerts, mail_blocked_by: nil, settings_href: nil, audit_href: AUDIT)
    render_inline(Admin::SystemStatusScreen::AlertsComponent.new(alerts: alerts, mail_blocked_by: mail_blocked_by,
      settings_href: settings_href, audit_href: audit_href))
  end

  test "no alerts is one line, and no notice even when mail is not set up" do
    card([], mail_blocked_by: :mail_not_ready)

    assert_selector "h2", text: "Alerts"
    assert_text "The last 7 days, newest first. Not part of the checks."
    assert_text "No alerts in the last 7 days."
    assert_no_selector "li"
    assert_no_selector "[role=alert]"
  end

  test "an error is a danger chip, its class and place in code, and Once · last time · Not mailed yet" do
    travel_to Time.zone.local(2026, 11, 16, 15, 0) do
      card([ error(last_seen_at: Time.zone.local(2026, 11, 16, 14, 2)) ])
    end

    assert_selector "li .admin-state-chip[data-state-tone=danger]", text: "Error"
    assert_selector "li code", text: "RuntimeError"
    assert_selector "li code", text: "app/models/page.rb:120"
    assert_text "Once · last 14:02 today · Not mailed yet"
    assert_no_link "Open audit log →"
  end

  test "an error with no place is its class alone" do
    card([ alert(kind: "error", details: { "error_class" => "RuntimeError", "place" => nil }) ])

    assert_selector "li code", count: 1, text: "RuntimeError"
  end

  test "a security alert is a warn chip, counts its times, says when it was mailed and links to the audit log" do
    travel_to Time.zone.local(2026, 11, 16, 15, 0) do
      card([ security(last_seen_at: Time.zone.local(2026, 11, 15, 9, 15), mailed_at: Time.zone.local(2026, 11, 16, 14, 2)) ])
    end

    assert_selector "li .admin-state-chip[data-state-tone=warn]", text: "Security"
    assert_text "21 failed sign-ins in 15 minutes"
    assert_text "12 times · last 09:15 yesterday · Mailed 14:02"
    assert_link "Open audit log →", href: AUDIT
  end

  test "a security row without an audit address has no link: the viewer may not open the audit log" do
    card([ security ], audit_href: nil)

    assert_text "21 failed sign-ins in 15 minutes"
    assert_no_link "Open audit log →"
  end

  test "an older time is a date, with the year when it is another year" do
    travel_to Time.zone.local(2026, 11, 16, 15, 0) do
      card([ error(last_seen_at: Time.zone.local(2026, 11, 14, 18, 3)), error(last_seen_at: Time.zone.local(2025, 12, 30, 8, 0)) ])
    end

    assert_text "last 14 Nov, 18:03"
    assert_text "last 30 Dec 2025, 08:00"
  end

  test "mail not ready: the notice at the top, the link only with an address, and the row's own sentence" do
    card([ error ], mail_blocked_by: :mail_not_ready, settings_href: "/cs-studio/settings#mail")

    assert_selector "[role=alert]", count: 0
    assert_text "Owners can't be mailed about these: outgoing mail is not set up."
    assert_link "Open Mail settings →", href: "/cs-studio/settings#mail"
    assert_selector "li span.text-warn-ink", text: "Not mailed: outgoing mail is not set up"
  end

  test "mail not ready without a settings link shows no link" do
    card([ error ], mail_blocked_by: :mail_not_ready)

    assert_text "Owners can't be mailed about these"
    assert_no_link "Open Mail settings →"
  end

  test "no site address: the notice says so and names PUBLIC_HOST, as an alert with no link, and the row says why" do
    card([ error ], mail_blocked_by: :no_address, settings_href: "/cs-studio/settings#mail")

    assert_selector "[role=alert]", count: 1,
      text: "Owners can't be mailed about these: the site has no address for the mail to link to. Set PUBLIC_HOST to the site's address."
    assert_no_link "Open Mail settings →"
    assert_selector "li span.text-warn-ink", text: "Not mailed: the site has no address"
    assert_no_text "Not mailed yet"
  end

  test "mail not set up wins over no address: one notice, and every row says mail" do
    card([ error, security ], mail_blocked_by: :mail_not_ready)

    assert_text "Owners can't be mailed about these: outgoing mail is not set up.", count: 1
    assert_no_text "the site has no address"
    assert_selector "li span.text-warn-ink", count: 2, text: "Not mailed: outgoing mail is not set up"
  end

  test "mail ready: no notice" do
    card([ error ])

    assert_no_text "Owners can't be mailed"
  end

  test "a secret in an error's stray keys is nowhere in the markup" do
    card([ alert(kind: "error", details: { "error_class" => "RuntimeError", "place" => nil, "message" => "password=hunter2", "params" => { "password" => "hunter2" } }) ])

    assert_no_text "hunter2"
    assert_no_match(/hunter2/, rendered_content)
  end

  test "every other kind words its sentence from the data" do
    card([
      alert(kind: "owner_changed", details: { "subject_label" => "Ana", "actor_name" => "Ben", "now_owner" => true }),
      alert(kind: "owner_changed", details: { "subject_label" => "Cleo", "actor_name" => nil, "now_owner" => false }),
      alert(kind: "token_issued", details: { "token_name" => "CI", "group_name" => "Editors", "actor_name" => nil }),
      alert(kind: "token_issued", details: { "token_name" => "Deploy", "group_name" => "Editors", "actor_name" => "Ben" }),
      alert(kind: "access_denied_burst", details: { "denied" => 22, "actors" => 1 }),
      alert(kind: "request_limited", details: { "limited" => 3, "limits" => %w[search forms] })
    ])

    assert_text "Ana was made an owner by Ben"
    assert_text "Cleo is no longer an owner"
    assert_text "API token “CI” issued"
    assert_text "API token “Deploy” issued by Ben"
    assert_text "22 actions refused in 15 minutes, by one account"
    assert_text "Limits on requests were reached 3 times in 15 minutes: search, forms"
  end
end
