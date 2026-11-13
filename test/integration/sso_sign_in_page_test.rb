require "test_helper"

# What the sign-in page draws of the site's single sign-on provider (Design
# System card StudioSingleSignOn, screens 1 to 3): the provider's button
# under the password form, the panel under SSO_REQUIRED with its owner path,
# a gem's sign-in method beside the provider's, and the provider's two
# refusal sentences in the panel's danger notice.
class SsoSignInPageTest < ActionDispatch::IntegrationTest
  setup { site_settings(:default).update!(setup_completed_at: Time.current) }

  # The provider's start: a POST form with its token, sent without Turbo,
  # since the provider is a whole page on another site.
  def provider_button = "form[action='#{admin_sso_path}'][method=post][data-turbo=false] button[type=submit]"
  # A button's look is the classes `ButtonComponent` draws its variant
  # with, asked of the component rather than spelled here.
  def look?(button, variant, size: :regular) = button["class"].to_s.include?(Admin::Ui::ButtonComponent.classes(variant, size: size))

  def assert_look(button, variant, size: :regular)
    assert look?(button, variant, size: size), "#{button.text.squish.inspect} is drawn as a #{size} #{variant}"
  end

  # The panel's primaries, by their words: one per panel.
  def primaries = css_select("main button").select { |button| look?(button, :primary) }.map { |button| button.text.squish }

  # The panel's ways in, in the order drawn: every button but the password
  # field's Show.
  def buttons_in_order = css_select("main button:not([data-password-field-target])").map { |button| button.text.squish }

  test "with a provider the page offers it under the form, as a secondary button before the passkey's" do
    with_sso do
      get admin_sign_in_path
      assert_response :success

      assert_select "form[action='#{admin_sign_in_path}'] input[name=email_address]"
      assert_select "form[action='#{admin_sign_in_path}'] input[name=password]"
      assert_select provider_button, text: "Sign in with Example ID", count: 1 do |button|
        assert_look button.first, :secondary
      end
      # The divider stands for the provider's button, which is always there,
      # so it is never hidden for want of a passkey.
      assert_select "[data-sign-in-divider]:not([hidden])", text: "or", count: 1

      order = buttons_in_order
      assert_equal [ "Sign in", "Sign in with Example ID", "Sign in with a passkey" ], order
      assert_equal [ "Sign in" ], primaries
      assert_select "a[href*='owner=1']", count: 0, text: "Owner sign-in"
    end
  end

  # The test environment turns forgery protection off, which drops every
  # form's token: it is turned on for the one page that shows it.
  test "the provider's form carries the form's token" do
    before = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    with_sso do
      get admin_sign_in_path
      assert_select "form[action='#{admin_sso_path}'] input[name=authenticity_token]", count: 1
    end
  ensure
    ActionController::Base.allow_forgery_protection = before
  end

  test "without a provider the page draws no provider button and keeps the passkey's own divider" do
    get admin_sign_in_path
    assert_select provider_button, count: 0
    assert_select "[data-sign-in-divider]", count: 0
    assert_select "[data-passkey-sign-in-target=divider][hidden]", text: "or"
  end

  test "with SSO required the provider is the primary, and the owner link opens the password form with its lead" do
    with_sso(required: true) do
      get admin_sign_in_path
      assert_response :success

      assert_select "h1", text: "Sign in"
      assert_select "main p", text: "This site signs you in with Example ID."
      assert_select provider_button, text: "Sign in with Example ID", count: 1 do |button|
        assert_look button.first, :primary
      end
      assert_select "input[name=password]", count: 0
      assert_select "button[data-passkey-sign-in-target=button]", count: 0
      assert_select "a[href='#{admin_sign_in_path(owner: 1)}']", text: "Owner sign-in"
      assert_equal [ "Sign in with Example ID" ], buttons_in_order

      get admin_sign_in_path(owner: 1)
      assert_response :success
      assert_select "h1", text: "Owner sign-in"
      assert_select "main p", text: "For owners only. Everyone else signs in with Example ID."
      assert_select "form[action='#{admin_sign_in_path}'] input[name=password]"
      assert_select "form[action='#{admin_sign_in_path}'] input[type=hidden][name=owner][value='1']"
      assert_select "button[data-passkey-sign-in-target=button]", text: "Sign in with a passkey"
      assert_select provider_button, text: "Sign in with Example ID instead", count: 1 do |button|
        assert_look button.first, :tertiary, size: :small
      end
      assert_equal [ "Sign in" ], primaries
      assert_select "a", text: "Owner sign-in", count: 0
    end
  end

  test "the owner parameter changes nothing while SSO is not required" do
    with_sso do
      get admin_sign_in_path(owner: 1)
      assert_select "h1", text: "Sign in"
      assert_select "main p", text: /For owners only/, count: 0
      assert_select provider_button, text: "Sign in with Example ID"
    end
  end

  # The ordinary refusal, and back on the owner path, so an owner who
  # mistyped can try again; the page says nothing of who is an owner.
  test "a non-owner who signs in on the owner path meets the ordinary refusal there" do
    with_sso(required: true) do
      post admin_sign_in_path, params: { email_address: users(:two).email_address, password: "password", owner: "1" }
      assert_redirected_to admin_sign_in_path(owner: 1)
      follow_redirect!
      assert_select "#alert", text: "Try another email address or password."
      assert_select "h1", text: "Owner sign-in"
      assert_equal 0, Session.count

      post admin_sign_in_path, params: { email_address: users(:one).email_address, password: "password", owner: "1" }
      assert_response :redirect
      assert_equal 1, Session.where(user: users(:one)).count
    end
  end

  test "a gem's sign-in method is a button on the page" do
    I18n.backend.store_translations(:en, acme: { sign_in: { saml: "Sign in with Acme" } })
    SignIn::Methods.register("acme/saml", label: "acme.sign_in.saml", path: :admin_root_path)
    get admin_sign_in_path
    assert_select "form[action='#{admin_root_path}'][method=post][data-turbo=false] button[type=submit]", text: "Sign in with Acme" do |button|
      assert_look button.first, :secondary
    end
    assert_select "[data-sign-in-divider]:not([hidden])", text: "or", count: 1
    assert_equal [ "Sign in", "Sign in with Acme", "Sign in with a passkey" ], buttons_in_order

    with_sso do
      get admin_sign_in_path
      assert_equal [ "Sign in", "Sign in with Example ID", "Sign in with Acme", "Sign in with a passkey" ], buttons_in_order
    end
    # SSO_REQUIRED neither hides nor refuses a gem's method; the owner path,
    # which no outside method signs into, does not draw it.
    with_sso(required: true) do
      get admin_sign_in_path
      assert_equal [ "Sign in with Example ID", "Sign in with Acme" ], buttons_in_order
      get admin_sign_in_path(owner: 1)
      assert_select "button", text: "Sign in with Acme", count: 0
    end
  ensure
    Rails.application.reloader.prepare!
    I18n.reload!
  end

  test "the refusal sentences name the provider" do
    with_fake_idp(email: "nobody-invited@example.com") do |idp|
      post admin_sso_path
      get idp.authorize(response.location)
      follow_redirect!
      assert_select "#alert", text: "Your Example ID account can't sign in to this site. Ask an owner to invite you."
      assert_select provider_button, text: "Sign in with Example ID"

      idp.deny!
      post admin_sso_path
      get idp.authorize(response.location)
      follow_redirect!
      assert_select "#alert", text: "Signing in with Example ID didn't finish. Try again."
    end
  end
end
