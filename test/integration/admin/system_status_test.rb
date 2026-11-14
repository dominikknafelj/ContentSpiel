require "test_helper"

# System status: the setup wizard's own read-only
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
      word = { ok: "OK", off: "Off" }.fetch(result.status, "Warning")
      assert_select "li", text: /#{word}.*#{Regexp.escape(result.label)}/m
    end
    assert_select "a[href='/cs-studio/system_status']", text: "Run checks again"
    assert_select "nav[aria-label='Modules'] a[href='/cs-studio/system_status']", text: "System status"
  end

  test "single sign-on not set up is an Off row drawn last, and counts as neither passed nor failed" do
    sign_in_as(users(:one))

    get "/cs-studio/system_status"

    rows = css_select("li.admin-system-check")
    assert_equal "off", rows.last["data-status"]
    assert_select "li[data-status=off]", text: /Off.*Single sign-on.*Not set up/m
    results = Setup::SystemCheck.run(remote_ip: "127.0.0.1").reject(&:off?)
    assert_select "p", text: /\A#{results.count(&:ok?)} of #{results.size} checks? passed/
  end

  # The page is shown to anyone with `system_status.view`: it names the
  # theme's folder and never where the server keeps it.
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

    # The request's own address makes the Visitor address row one of them.
    results = Setup::SystemCheck.run(remote_ip: "127.0.0.1")
    assert_select "h1.text-h1", text: "System status"
    # Off rows are in neither count.
    results = results.reject(&:off?)
    assert_select "h1 + p.text-small.text-meta", text: "#{results.count(&:ok?)} of #{results.size} checks passed · last run 17:30"
    assert_select "a[href='/cs-studio/system_status'][class=?]", Admin::Ui::ButtonComponent.classes(:secondary), text: "Run checks again"
  end

  # The summary is plural by the total: no site runs a single check, so the
  # `one` form is read from the key itself.
  test "the summary's words follow the total's plural" do
    words = ->(passed, count) { I18n.t("admin.system_status.show.summary", passed: passed, count: count, time: "17:30") }

    assert_equal "1 of 1 check passed · last run 17:30", words.(1, 1)
    assert_equal "5 of 6 checks passed · last run 17:30", words.(5, 6)
  end

  # One card holds the rows, divided inside it; the wizard keeps its own
  # ruled list (`setup/_system_check_results`'s default frame).
  test "the checks are one card with their rows divided inside it, and no summary chip" do
    sign_in_as(users(:one))

    get "/cs-studio/system_status"

    assert_select "div.rounded-card.bg-surface.shadow-1", count: 1 do
      assert_select "> ul.divide-y.divide-line.px-4", count: 1 do
        assert_select "> li.admin-system-check", count: Setup::SystemCheck.run(remote_ip: "127.0.0.1").size
      end
    end
    assert_select "ul.border-y", count: 0
    assert_select ".admin-system-check-summary, [data-summary-chip]", count: 0
  end

  test "Visitor address reads the request: OK without Cloudflare's header, and a warning with a link when it is not the address counted" do
    sign_in_as(users(:one))

    get "/cs-studio/system_status"
    assert_select "li.admin-system-check[data-status=ok]", text: /Visitor address\s+Each visitor counts by the address their request comes from\./

    get "/cs-studio/system_status", headers: { "CF-Connecting-IP" => "203.0.113.5" }
    assert_select "li.admin-system-check[data-status=warning]", text: /Visitor address/ do
      assert_select "p", text: /Set TRUSTED_PROXIES to Cloudflare's ranges\./
      assert_select "a[href=?]", Setup::SystemCheck::VISITOR_ADDRESS_DOCS, text: "Learn more →"
    end

    get "/cs-studio/system_status", headers: { "CF-Connecting-IP" => "127.0.0.1" }
    assert_select "li.admin-system-check[data-status=ok]", text: /Visitor address\s+Requests come through Cloudflare, and the visitor's own address is read\./
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

      assert_select "[data-controller='admin--ui--clipboard'] code[data-admin--ui--clipboard-target=source]", text: Setup::SystemCheck::MAIL_FALLBACK_COMMAND
    end
    [ :working, :failed ].each do |state|
      with_mail_state(state) do
        get "/cs-studio/system_status"

        assert_select "code", text: Setup::SystemCheck::MAIL_FALLBACK_COMMAND, count: 0
      end
    end
  end

  test "the Images row links to Settings → Images for settings.manage and to nothing otherwise" do
    Media::Asset.delete_all
    create_media_asset.update_columns(renditions_fingerprint: "other") # version: none (a test)

    sign_in_as(users(:one))
    get "/cs-studio/system_status"
    assert_select "li[data-status=warning]", text: /Images.*still being made/m do
      assert_select "a[href=?]", "/cs-studio/settings#images", text: "Open Image settings →"
    end

    viewer = users(:reader)
    access_control_groups(:read_only).grants.create!(permission: "system_status.view", scope: {})
    sign_in_as(viewer)
    get "/cs-studio/system_status"
    assert_select "li", text: /Images.*still being made/m
    assert_select "a", text: "Open Image settings →", count: 0
  end

  test "the Forms row is on the screen, with its link when submissions weren't delivered" do
    sign_in_as(users(:one))
    with_mail_state(:working) do
      get "/cs-studio/system_status"
      assert_select "li[data-status=ok]", text: /Forms.*Forms are working\./m
      assert_select "a", text: "Open Forms →", count: 0

      submission = Forms::Submission.create!(form: forms(:contact), locale: "en", answers: [])
      Forms::Delivery.create!(submission: submission, kind: "mail", state: "failed")
      get "/cs-studio/system_status"
      assert_select "li[data-status=warning]", text: /Forms.*1 submission wasn't delivered\./m do
        assert_select "a[href=?]", "/cs-studio/forms", text: "Open Forms →"
      end
    end
  end

  test "a viewer of System status without the Forms rights sees the undelivered warning and no link" do
    submission = Forms::Submission.create!(form: forms(:contact), locale: "en", answers: [])
    Forms::Delivery.create!(submission: submission, kind: "mail", state: "failed")
    access_control_groups(:read_only).grants.create!(permission: "system_status.view", scope: {})
    sign_in_as(users(:reader))

    with_mail_state(:working) do
      get "/cs-studio/system_status"
      assert_select "li[data-status=warning]", text: /1 submission wasn't delivered\./
      assert_select "a", text: "Open Forms →", count: 0
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
      rows.each { |row| assert_match(/\A\s*(OK|Warning|Off)\b/, row.css("span").first.text.strip) }
    end
    assert_select "li.admin-system-check span[aria-hidden=true]"
  end

  test "the page needs system_status.view" do
    sign_in_as(users(:reader))

    get "/cs-studio/system_status"

    assert_response :forbidden
  end
end
