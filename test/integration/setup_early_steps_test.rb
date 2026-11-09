require "test_helper"

class SetupEarlyStepsTest < ActionDispatch::IntegrationTest
  setup do
    start_fresh_install
    verify_setup_token
  end

  test "the system check lists every check and can be continued" do
    get setup_step_path("system_check")

    assert_response :success
    %w[Site\ address File\ storage Image\ processing Background\ jobs Mail].each do |label|
      assert_includes response.body, label
    end
    assert_select "a[href=?]", setup_step_path("admin"), text: "Continue"
  end

  # The wizard loads `application` only, where `admin--ui--clipboard` doesn't
  # exist: the shared rows must not draw a Copy button there.
  test "the system check shows the site address command but no dead Copy button" do
    get setup_step_path("system_check")

    assert_select "code", text: Setup::SystemCheck::SITE_ADDRESS_COMMAND
    assert_select "button", text: "Copy", count: 0
    assert_select "[data-controller='admin--ui--clipboard']", count: 0
  end

  # The wizard is where a new site is first seen, often before its address
  # and its certificate are in place: it says both, from this request.
  test "the system check says how this request came, in production only, and what the site's address is" do
    get setup_step_path("system_check")
    assert_select "li.admin-system-check", text: /HTTPS/, count: 0

    was = Rails.env
    begin
      Rails.env = "production"
      get setup_step_path("system_check")
    ensure
      Rails.env = was
    end
    assert_select "li.admin-system-check[data-status=warning]", text: /HTTPS\s+This page was reached over plain HTTP\./

    with_site_address(nil) do
      get setup_step_path("system_check")

      assert_select "li.admin-system-check[data-status=warning]", text: /Site address\s+No site address is set\./ do
        assert_select "code", text: "PUBLIC_HOST=https://www.example.org"
      end
      assert_select "button", text: "Copy", count: 0
    end
  end

  test "the system check says of reset mails what is true where it runs: from the request here, not sent in production" do
    with_site_address(nil) do
      get setup_step_path("system_check")
      assert_select "li.admin-system-check[data-status=warning]", text: /Addresses in pages and in password reset mails follow the request\./

      was = Rails.env
      begin
        Rails.env = "production"
        get setup_step_path("system_check")
      ensure
        Rails.env = was
      end
      assert_select "li.admin-system-check[data-status=warning]", text: /password reset mails are not sent until it is set\./
    end
  end

  # The admin step takes a password, and nobody is signed in: the notice is
  # for everyone, as on the sign-in page.
  test "in production over plain HTTP every wizard page says the connection is not encrypted, and nothing says so otherwise" do
    notice = "This connection is not encrypted. Passwords and sessions can be read on the way. Set PUBLIC_HOST to an https address."

    %w[system_check admin].each do |step|
      get setup_step_path(step)

      assert_response :success
      assert_select "#insecure-notice", count: 0
    end

    was = Rails.env
    begin
      Rails.env = "production"
      %w[system_check admin].each do |step|
        get setup_step_path(step)

        assert_response :success
        assert_select "main p#insecure-notice[role=alert]", text: notice, count: 1
      end

      https!
      get setup_step_path("admin")

      assert_response :success
      assert_select "#insecure-notice", count: 0
    ensure
      Rails.env = was
    end
  end

  test "the token step welcomes, says Step 1 of 9 and has one primary" do
    get setup_step_path("token")

    assert_response :success
    assert_select "main", text: /Welcome to Content·Spiel/ do
      assert_select "span[aria-hidden=true].bg-ic-structure-bg"
    end
    assert_select "h1", text: "Let's set up your site"
    assert_select "nav[aria-label='Setup steps']" do
      assert_select "[aria-hidden=true] > span.bg-accent[style='width: 11%']"
      assert_select "p", text: "Step 1 of 9"
    end
    primary = Admin::Ui::ButtonComponent.classes(:primary)
    assert_equal [ "Continue" ], css_select("[class]").select { |node| node["class"].include?(primary) }.map { |node| node.text.strip }
    assert_select "details > summary", text: "Where do I find the log?"
    assert_select "details code.font-cs-mono", text: "docker compose logs web"
  end

  # The log help names four commands, and each must exist: a person who runs
  # one that does not finds no token. `contentspiel dev` runs compose in the
  # foreground (`install/contentspiel`), so its terminal is where the log is.
  test "the log help names only commands that exist, and says a token set in SETUP_TOKEN is not printed" do
    get setup_step_path("token")

    commands = css_select("details code").map { |node| node.text.strip }
    assert_equal [ "SETUP_TOKEN", "bin/dev", "docker compose logs web", "kamal app logs", "contentspiel dev" ], commands
    assert_select "details p", text: "The setup token is printed in the server's log when CS Studio starts, unless you set it yourself with SETUP_TOKEN."
    assert_select "details p", text: "With the contentspiel command: the terminal running contentspiel dev."

    assert Rails.root.join("bin/dev").executable?
    assert_match(/^services:.*^\s+<%= service %>:/m, Rails.root.join("lib/site_template/compose.yml.tt").read)
    assert_includes Rails.root.join("lib/site_template/compose.yml.tt").read, "%w[web css]"
    assert_match(/^gem "kamal"/, Rails.root.join("Gemfile").read)
    assert_match(/if \[ "\$\{1:-\}" = dev \]; then.*docker compose -f \.contentspiel\/compose\.yml up/m, Rails.root.join("install/contentspiel").read)
  end

  test "a step names itself current, the earlier ones done in the ok tone, and Optional in words" do
    get setup_step_path("admin")

    assert_select "nav[aria-label='Setup steps'] li[aria-current=step]", count: 1, text: /Admin account/ do
      assert_select "span.border-accent.text-accent", text: "3"
    end
    assert_select "nav[aria-label='Setup steps'] li", text: /Setup token/ do
      assert_select "span.bg-ok-tint.text-ok-ink svg"
      assert_select ".sr-only", text: "Done:"
    end
    assert_select "nav[aria-label='Setup steps'] li", text: /System check\s+Optional/ do
      assert_select "span.text-label.text-meta", text: "Optional"
    end
    assert_select "nav[aria-label='Setup steps'] li", text: /Site identity/ do
      assert_select "span.border-field-line.text-meta", text: "4"
    end
    assert_select "nav[aria-label='Setup steps'] .bg-live", count: 0
    assert_select "nav[aria-label='Setup steps'] p", text: "Step 3 of 9"
    assert_select "header", text: /Content·Spiel/
    assert_select "header", text: /First-run setup/
    assert_select "[role=radiogroup][aria-label='Theme']"
  end

  test "setup.steps holds exactly the steps" do
    assert_equal SetupController::STEPS, I18n.t("setup.steps").keys.map(&:to_s)
  end

  test "the admin step failing shows the error summary and keeps field names" do
    patch setup_step_path("admin"), params: { user: { email_address: "owner@example.com", password: "short", password_confirmation: "short" } }

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /Use at least 12 characters\./
    assert_select "input[name='user[email_address]']"
    assert_select "input[name='user[password]']"
    assert_select "input[name='user[password_confirmation]']"
    assert_select "button", text: "Continue"
  end

  test "creating the admin signs them in and moves to site identity" do
    assert_difference "User.count", 1 do
      create_setup_admin
    end

    assert_redirected_to setup_step_path("site")
    assert_equal "owner@example.com", User.last.email_address
    assert User.last.owner?, "the first account is the owner"
  end

  test "a password confirmation mismatch is shown, nothing is created" do
    assert_no_difference "User.count" do
      patch setup_step_path("admin"), params: { user: {
        email_address: "owner@example.com", password: "password12345", password_confirmation: "different"
      } }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Password confirmation doesn&#39;t match"
  end

  test "a blank email is rejected" do
    patch setup_step_path("admin"), params: { user: { email_address: " ", password: "password12345", password_confirmation: "password12345" } }

    assert_response :unprocessable_entity
    assert_includes response.body, "Email address can&#39;t be blank"
  end

  test "the admin step can't be repeated once an admin exists" do
    create_setup_admin

    get setup_step_path("admin")

    assert_redirected_to setup_step_path("site")
  end
end
