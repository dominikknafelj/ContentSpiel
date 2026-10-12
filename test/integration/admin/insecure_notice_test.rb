require "test_helper"

# The plain-HTTP notice (`Admin::Ui::InsecureNoticeComponent`) and the two
# checks that say the same on System status and in the setup wizard: where
# each is drawn, for whom, and that nothing is said outside production.
#
# `as_production` changes `Rails.env` for one block in this process (a
# parallel worker is a process of its own). Nothing else in the app reads
# the environment while a page is drawn but `PasswordsMailer`, which no
# request here reaches.
class Admin::InsecureNoticeTest < ActionDispatch::IntegrationTest
  NOTICE = "This connection is not encrypted. Passwords and sessions can be read on the way. Set PUBLIC_HOST to an https address.".freeze

  setup { site_settings(:default).update!(setup_completed_at: Time.current) }

  test "in the test environment sign-in, the password pages and CS Studio show nothing" do
    [ "/cs-studio/sign-in", new_admin_password_path, admin_edit_password_path(users(:one).password_reset_token) ].each do |path|
      get path

      assert_response :success
      assert_select "#insecure-notice", count: 0
    end

    sign_in_as(users(:one))
    get "/cs-studio/system_status"

    assert_response :success
    assert_select "#insecure-notice", count: 0
    assert_select "li.admin-system-check", text: /HTTPS/, count: 0
  end

  test "in production over plain HTTP sign-in and both password pages say so, to everyone" do
    as_production do
      [ "/cs-studio/sign-in", new_admin_password_path, new_admin_password_path(sent: 1),
        admin_edit_password_path(users(:one).password_reset_token) ].each do |path|
        get path

        assert_response :success
        assert_select "main p#insecure-notice[role=alert]", text: NOTICE, count: 1
      end
    end
  end

  test "in production over an encrypted connection they say nothing" do
    https!
    as_production do
      [ "/cs-studio/sign-in", new_admin_password_path ].each do |path|
        get path

        assert_response :success
        assert_select "#insecure-notice", count: 0
      end
    end
  end

  test "in the shell it is shown to someone who may change the settings or see System status, on any screen" do
    sign_in_as(users(:one))

    as_production do
      get "/cs-studio"

      assert_response :success
      assert_select "main.admin-shell__main > p#insecure-notice[role=alert]", text: NOTICE, count: 1
      # Outside the content frame: a frame navigation keeps it.
      assert_select "turbo-frame#content #insecure-notice", count: 0
    end
  end

  test "in the shell someone who holds neither right is told nothing" do
    sign_in_as(users(:reader))

    as_production do
      get "/cs-studio"

      assert_response :success
      assert_select "#insecure-notice", count: 0
    end
  end

  test "in the shell over an encrypted connection nobody is told anything" do
    https!
    sign_in_as(users(:one))

    as_production do
      get "/cs-studio"

      assert_response :success
      assert_select "#insecure-notice", count: 0
    end
  end

  test "System status hands the checks how this request came: a warning over plain HTTP, OK when encrypted" do
    sign_in_as(users(:one))

    as_production do
      get "/cs-studio/system_status"

      assert_select "li.admin-system-check[data-status=warning]", text: /HTTPS\s+This page was reached over plain HTTP\./
    end

    https!
    as_production do
      get "/cs-studio/system_status"

      assert_select "li.admin-system-check[data-status=ok]", text: /HTTPS\s+This page was reached over an encrypted connection\./
    end
  end

  test "System status names the site's address, or says none is set and shows the variable to copy" do
    sign_in_as(users(:one))

    with_site_address("https://docs.example.org") do
      get "/cs-studio/system_status"

      assert_select "li.admin-system-check[data-status=ok]", text: /Site address\s+This site answers at https:\/\/docs\.example\.org\./
    end

    with_site_address(nil) do
      get "/cs-studio/system_status"

      assert_select "li.admin-system-check[data-status=warning]", text: /Site address\s+No site address is set\./ do
        assert_select "code", text: "PUBLIC_HOST=https://www.example.org"
        assert_select "button[aria-label='Copy command for Site address']", text: "Copy"
      end
    end
  end

  private
    def as_production
      was = Rails.env
      Rails.env = "production"
      yield
    ensure
      Rails.env = was
    end
end
