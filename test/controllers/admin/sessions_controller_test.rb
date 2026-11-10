require "test_helper"

class Admin::SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = User.take }

  test "new" do
    get admin_sign_in_path
    assert_response :success
  end

  test "sign-in shows Forgot your password? only when mail is ready, and the owner line otherwise" do
    with_mail_state(:working) do
      get admin_sign_in_path
      assert_select "a[href='#{new_admin_password_path}']", text: "Forgot your password?"
      assert_select "main", text: /Ask the site's owner/, count: 0
    end
    with_mail_state(:failed) do
      get admin_sign_in_path
      assert_select "a", text: "Forgot your password?"
    end
    %i[ not_set_up untested ].each do |state|
      with_mail_state(state) do
        get admin_sign_in_path
        assert_select "a", text: "Forgot your password?", count: 0
        assert_select "p.text-meta", text: "Forgot your password? Ask the site's owner to reset it."
        assert_select "main", text: /console|bin\/rails/i, count: 0
      end
    end
  end

  test "sign-in uses the product shell: wordmark, theme switch, labelled fields, token button" do
    get admin_sign_in_path
    assert_select "header a", text: "CONTENT·SPIEL"
    assert_select "[role=radiogroup][aria-label='Theme']"
    assert_select "label[for=email_address]", text: "Email"
    assert_select "label[for=password]", text: "Password"
    assert_select "button.bg-accent", text: "Sign in"
    assert_no_match(/bg-blue|rounded-(md|lg|xl)/, response.body)
  end

  # The sign-in pages stand on one panel, the setup wizard's: a surface at
  # elevation 2 in a 420px column, the site's name over a heading on the
  # type scale, every alert the compact notice, and the full-width submit
  # the one primary. "Forgot your password?" is a tertiary link on the
  # Password label row.
  test "the sign-in page is one panel with one primary, its alerts the compact notice" do
    put_mail_state(:working)
    post admin_sign_in_path, params: { email_address: @user.email_address, password: "wrong" }
    follow_redirect!

    assert_select "main > div.mx-auto.w-full.max-w-\\[420px\\] > div.rounded-rail.bg-surface.p-6.shadow-2", count: 1 do
      assert_select ".admin-site-name.text-small.text-dim + h1.text-h1.font-semibold.break-words", text: "Sign in"
      assert_select ".admin-site-name", text: site_settings(:default).title
      assert_select "div#alert[role=alert].rounded-card.bg-danger-tint.text-small", text: "Try another email address or password."
      assert_select ".admin-field label[for=email_address]", text: "Email"
      assert_select ".admin-password-field > div.justify-between label[for=password]"
      assert_equal Admin::Ui::ButtonComponent.classes(:tertiary, size: :small), css_select("a[href='#{new_admin_password_path}']").sole["class"]
    end
    assert_select "main .bg-accent", count: 1
    assert_select "main button[type=submit].bg-accent.w-full", text: "Sign in"
    assert_select "main .rounded-cs.bg-danger-tint", count: 0
  end

  test "a failed sign-in shows one alert line above the form" do
    post admin_sign_in_path, params: { email_address: @user.email_address, password: "wrong" }
    follow_redirect!
    assert_select "[role=alert]", text: "Try another email address or password.", count: 1
  end

  test "create with valid credentials" do
    post admin_sign_in_path, params: { email_address: @user.email_address, password: "password" }

    assert_redirected_to admin_root_path
    assert cookies[:session_id]
  end

  test "create with invalid credentials" do
    post admin_sign_in_path, params: { email_address: @user.email_address, password: "wrong" }

    assert_redirected_to admin_sign_in_path
    assert_nil cookies[:session_id]
  end

  test "destroy" do
    sign_in_as(User.take)

    delete admin_sign_out_path

    assert_redirected_to admin_sign_in_path
    assert_empty cookies[:session_id]
  end
end
