require "test_helper"

# "Continue with <provider>" on the invitation page (`InvitationsController#sso`):
# the token in the body, the start from the invitation, and what the page
# draws before and after the provider. The fake provider is on 127.0.0.1
# (`OidcHelper`).
class InvitationSsoTest < ActionDispatch::IntegrationTest
  PAGE = "/#{ContentSpiel::ADMIN_PATH}/invitation".freeze
  SSO = "#{PAGE}/sso".freeze
  EMAIL = "newcomer@example.com".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @invitation = open_invitation(EMAIL, name: "Newcomer")
    @token = @invitation.generate_token_for(:accept)
  end

  def start(token: @token) = post(SSO, params: { token: token })

  test "Continue with the provider accepts the invitation and signs the new person in, linked" do
    with_fake_idp(email: EMAIL, name: "Prov Name") do |idp|
      start
      assert_response :see_other
      assert response.location.start_with?("#{idp.issuer}/authorize?")
      assert_equal @invitation.id, kept_state["invitation_id"]
      assert_equal "invitation", kept_state["intent"]

      get idp.authorize(response.location)
      assert_redirected_to admin_root_url
      follow_redirect!
      assert_select "body", /Your account is ready\./

      user = User.find_by!(email_address: EMAIL)
      assert @invitation.reload.accepted?
      assert user.sso_linked?
      assert_equal "Prov Name", user.name
      assert_equal [ user.id, "sso" ], Session.sole.values_at(:user_id, :authenticated_with)
    end
  end

  test "an existing account's sign-in through the provider carries no ready toast" do
    with_fake_idp do |idp|
      post admin_sso_path
      get idp.authorize(response.location)
      follow_redirect!
      assert_select "body", text: /Your account is ready\./, count: 0
    end
  end

  test "another verified email comes back to the page naming both addresses, and the page draws only that notice" do
    with_fake_idp(email: "someone-else@example.com") do |idp|
      start
      get idp.authorize(response.location)
      assert_redirected_to admin_invitation_path
      assert_equal 0, Session.count
      assert_not @invitation.reload.accepted?

      follow_redirect!
      assert_response :success
      assert_select "#alert", /Example ID signed you in as someone-else@example\.com, but this invitation is for #{Regexp.escape(EMAIL)}\./
      assert_select "#alert", /Open the link in your invitation mail again/
      assert_select "form", count: 0
      assert_select "[data-controller=invitation-token]", count: 0
    end
  end

  test "a provider that cannot be reached comes back to the page with the notice alone and the way on" do
    with_fake_idp do |idp|
      idp.answer_discovery_with(status: 500, body: { "error" => "down" })
      start
      assert_redirected_to admin_invitation_path

      follow_redirect!
      assert_select "#alert", /Signing in with Example ID didn't finish\./
      assert_select "#alert", /Open the link in your invitation mail again/
      assert_select "form", count: 0
    end
  end

  test "a lapsed or used token gets the page's own answer and goes nowhere" do
    with_fake_idp(email: EMAIL) do
      start(token: "not-a-token")
      assert_response :unprocessable_entity
      assert_select "[data-invitation-token-target='expired']:not([hidden])", count: 1

      User.create!(email_address: EMAIL, password: "a-new-long-password-1")
      start
      assert_response :unprocessable_entity
      assert_select "[data-invitation-token-target='used']:not([hidden])", count: 1
      assert_not Array(response.headers["Set-Cookie"]).join("\n").include?("cs_sso_state=")
    end
  end

  test "without a provider the start is a 404" do
    start
    assert_response :not_found
  end

  test "the page offers the provider after the password form and an or, as a secondary" do
    with_fake_idp do
      get PAGE
      assert_select "form[action=?]", PAGE
      assert_select "[data-invitation-token-target=ways][hidden]" do
        assert_select "[aria-hidden=true]", text: /or/
        assert_select "form[action=?][data-turbo=false] button", SSO, text: "Continue with Example ID"
      end
      assert_not_includes response.body, @token
    end
  end

  test "without a provider the page has no second way" do
    get PAGE
    assert_select "[data-invitation-token-target=ways]", count: 0
    assert_select "form[action=?]", SSO, count: 0
  end

  test "under SSO_REQUIRED the page shows only the provider's button" do
    with_fake_idp(required: true) do
      get PAGE
      assert_response :success
      assert_select "form[action=?]", "/#{ContentSpiel::ADMIN_PATH}/invitation", count: 0
      assert_select "input[name=password]", count: 0
      assert_select "form[action=?] button", SSO, text: "Continue with Example ID", count: 1
      assert_select "[aria-hidden=true]", text: /or/, count: 0
      assert_select "input[type=hidden][name=token][data-invitation-token-target=token]", count: 1
      assert_select "[data-invitation-token-target=form][data-action~='submit->invitation-token#carryToken']", count: 1, message: "the token is carried to the provider's form"
    end
  end

  private

  def kept_state
    jar = ActionDispatch::TestRequest.create.cookie_jar
    jar[SsoStarts::STATE_COOKIE.to_s] = cookies[SsoStarts::STATE_COOKIE.to_s]
    jar.encrypted[SsoStarts::STATE_COOKIE.to_s]
  end
end
