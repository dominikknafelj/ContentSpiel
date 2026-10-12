require "test_helper"

class SetupEarlyStepsTest < ActionDispatch::IntegrationTest
  setup do
    start_fresh_install
    verify_setup_token
  end

  test "the system check lists every check and can be continued" do
    get setup_step_path("system_check")

    assert_response :success
    %w[Site\ address File\ storage Image\ processing Background\ jobs Outgoing\ mail].each do |label|
      assert_includes response.body, label
    end
    assert_select "a[href=?]", setup_step_path("admin"), text: "Continue"
  end

  # The wizard loads `application` only, where `admin--ui--clipboard` doesn't
  # exist: the shared rows must not draw a Copy button there.
  test "the system check shows the mail command but no dead Copy button" do
    get setup_step_path("system_check")

    assert_select "code", text: Setup::SystemCheck::MAIL_FALLBACK_COMMAND
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

  test "the step list marks the current step, done steps and optional ones" do
    get setup_step_path("admin")

    assert_select "nav[aria-label='Setup steps'] li[aria-current=step]", text: /Admin account/
    assert_select "nav[aria-label='Setup steps'] li", text: /✓.*Setup token/m
    assert_select "nav[aria-label='Setup steps'] li", text: /System check\s+optional/
    assert_select "header", text: /Content·Spiel/
    assert_select "[role=radiogroup][aria-label='Theme']"
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
