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

  # The page is shown to anyone with `system_status.view`: it names the
  # theme's folder and never where the server keeps it (theming spec §1).
  #
  # And it says when the stylesheet is not that theme's, with the stamp the
  # build wrote (`ThemeFolder.stamp`), read for real here: this suite's
  # stylesheet is built for the default theme, so the default theme's row is
  # OK and the second theme's is the warning, with the command that builds
  # it. (The OK wording under a theme is the model's test: making it true
  # here would mean writing app/assets/builds, which every other test reads.)
  test "the theme row names the theme that draws the site and no path of the server, and warns when the stylesheet is another theme's" do
    sign_in_as(users(:one))

    get "/cs-studio/system_status"
    assert_select "li[data-status=ok]", text: /Theme.*The default theme draws the site \(THEME_PATH is not set\)\./m

    with_plain_theme do
      get "/cs-studio/system_status"

      assert_select "li[data-status=warning]", text: /Theme.*The theme “plain” is set, but the stylesheet was built for another theme/m
      assert_select "li[data-status=warning]", text: /Theme.*#{Regexp.escape(Setup::SystemCheck::STYLESHEET_COMMAND)}/m
      assert_not_includes response.body, ThemeTestHelper::PLAIN.dirname.to_s
      assert_not_includes response.body, Theme.current.fingerprint
      assert_not_includes response.body, Theme.current.fingerprint[0, 9]
      assert_not_includes response.body, ThemeFolder::STAMP
    end
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

  include MailState

  test "the Mail row shows each state's words, and a failure's sentence and never the server's line" do
    sign_in_as(users(:one))

    with_mail_state(:failed) do
      Current.site.update_columns(mail_failure: { "key" => "login", "line" => "535 5.7.8 Authentication failed for ana" }) # version: none (a test)
      Current.site = nil
      get "/cs-studio/system_status"

      assert_select "li[data-status=warning]", text: /Mail/ do
        assert_select "p", text: /Last send failed .*: the server refused the login\./
      end
      assert_no_match(/535 5\.7\.8|Authentication failed/, response.body)
      # users(:one) holds settings.manage: the link is offered.
      assert_select "li[data-status=warning] a[href=?]", "/cs-studio/settings#mail", text: "Open Mail settings →"
    end

    with_mail_state(:working) do
      get "/cs-studio/system_status"

      assert_select "li[data-status=ok]", text: /Working\. Last mail sent/
    end
  end

  test "the Mail row carries the copyable command while mail is not ready, and none once it works" do
    sign_in_as(users(:one))

    with_mail_state(:untested) do
      get "/cs-studio/system_status"

      assert_select "[data-controller='admin--ui--clipboard'][data-admin--ui--clipboard-text-value=?]", Setup::SystemCheck::MAIL_FALLBACK_COMMAND
    end
    [ :working, :failed ].each do |state|
      with_mail_state(state) do
        get "/cs-studio/system_status"

        assert_select "code", text: Setup::SystemCheck::MAIL_FALLBACK_COMMAND, count: 0
      end
    end
  end

  test "someone who may view System status but not manage Settings is shown the state and no link" do
    viewer = users(:reader)
    access_control_groups(:read_only).grants.create!(permission: "system_status.view", scope: {})
    sign_in_as(viewer)

    with_mail_state(:failed) do
      Current.site.update_columns(mail_failure: { "key" => "login", "line" => "535 5.7.8 Authentication failed for ana" }) # version: none (a test)
      Current.site = nil
      get "/cs-studio/system_status"

      assert_response :ok
      assert_select "li", text: /Last send failed .*: the server refused the login\./
      assert_no_match(/535 5\.7\.8|Authentication failed/, response.body)
      assert_select "a", text: "Open Mail settings →", count: 0
    end

    with_mail_state(:untested) do
      get "/cs-studio/system_status"

      assert_response :ok
      assert_select "li", text: /Saved, not tested/
      assert_select "li", text: /Mail/ do
        assert_select "code", text: Setup::SystemCheck::MAIL_FALLBACK_COMMAND
      end
      assert_select "a", text: "Open Mail settings →", count: 0
    end
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
