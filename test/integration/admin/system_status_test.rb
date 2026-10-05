require "test_helper"

# System status (design spec §6.1): the setup wizard's own read-only
# `Setup::SystemCheck` results, re-run on every load ("Run again" is a
# plain reload), with a summary, warnings first and a copyable command.
class Admin::SystemStatusTest < ActionDispatch::IntegrationTest
  setup { site_settings(:default).update!(setup_completed_at: Time.current) }

  test "requires sign-in" do
    get "/cs-studio/system_status"
    assert_redirected_to "/cs-studio/sign-in"
  end

  test "renders every SystemCheck result, with Run checks again" do
    sign_in_as(users(:one))

    get "/cs-studio/system_status"

    assert_response :success
    Setup::SystemCheck.run.each do |result|
      assert_select "li", text: /#{result.ok? ? "OK" : "Warning"}.*#{Regexp.escape(result.label)}/m
    end
    assert_select "a[href='/cs-studio/system_status']", text: "Run checks again"
    assert_select "nav[aria-label='Modules'] a[href='/cs-studio/system_status']", text: "System status"
  end

  test "the summary counts passed checks and names the last run in the site time zone" do
    site_settings(:default).update!(time_zone: "Tokyo")
    sign_in_as(users(:one))

    travel_to Time.utc(2026, 10, 4, 8, 30) do
      get "/cs-studio/system_status"
    end

    results = Setup::SystemCheck.run
    assert_select "h1 + p", text: "#{results.count(&:ok?)} of #{results.size} checks passed · last run 17:30"
  end

  test "warnings are listed before OK rows" do
    sign_in_as(users(:one))

    get "/cs-studio/system_status"

    statuses = css_select("li.admin-system-check").map { |row| row["data-status"] }
    assert_equal statuses.sort_by { |status| status == "warning" ? 0 : 1 }, statuses
  end

  test "the mail warning shows its command, as text, with a Copy button carrying it" do
    sign_in_as(users(:one))

    get "/cs-studio/system_status"

    # The test environment sends no real mail, so the warning is always there.
    command = Setup::SystemCheck::MAIL_FALLBACK_COMMAND
    assert_select "li[data-status=warning]", text: /Outgoing mail/
    assert_select "[data-controller='admin--clipboard'][data-admin--clipboard-text-value=?]", command
    assert_select "code", text: command
    assert_select "button[data-action='click->admin--clipboard#copy']", text: "Copy"
  end

  test "a status is a dot and a word, never colour alone" do
    sign_in_as(users(:one))

    get "/cs-studio/system_status"

    assert_select "li.admin-system-check" do |rows|
      rows.each { |row| assert_match(/\A\s*(OK|Warning)\b/, row.css("span").first.text.strip) }
    end
    assert_select "li.admin-system-check span[aria-hidden=true]"
  end

  test "the page needs system_status.view" do
    sign_in_as(users(:reader))

    get "/cs-studio/system_status"

    assert_response :forbidden
  end
end
