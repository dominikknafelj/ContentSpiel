require "test_helper"

class Admin::SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = User.take }

  test "new" do
    get admin_sign_in_path
    assert_response :success
  end

  test "sign-in uses the product shell: wordmark, theme switch, labelled fields, token button" do
    get admin_sign_in_path
    assert_select "header a", text: "CONTENT·SPIEL"
    assert_select "[role=radiogroup][aria-label='Theme']"
    assert_select "label[for=email_address]", text: "Email"
    assert_select "label[for=password]", text: "Password"
    assert_select "button.bg-accent", text: "Sign in"
    assert_select "a", text: "Forgot your password?"
    assert_no_match(/bg-blue|rounded-(md|lg|xl)/, response.body)
  end

  # Handoff "Studio Sign In": the form sits directly on the page, 360px wide, no
  # card; the site name (default language) above a 28px heading; "Forgot your
  # password?" right-aligned on the Password label row, 12px, not underlined.
  test "sign-in has no card, the site name above the heading, and the forgot link on the password label row" do
    get admin_sign_in_path
    assert_select "main div.bg-surface.border", count: 0
    assert_select "main > div.max-w-\\[360px\\]"
    assert_select ".admin-site-name + h1.font-semibold", text: "Sign in"
    assert_select ".admin-site-name", text: site_settings(:default).title
    assert_select ".admin-password-field > div.justify-between label[for=password]"
    assert_select ".admin-password-field > div.justify-between a.text-xs", text: "Forgot your password?"
    assert_select "a.underline", count: 0
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
