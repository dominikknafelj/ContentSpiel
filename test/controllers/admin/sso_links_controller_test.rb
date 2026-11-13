require "test_helper"

# "Unlink…" in the user editor's Single sign-on zone: owner only, answered by
# `Sso::Unlink`; the zone and the badge are drawn for an owner viewer and a
# linked user.
class Admin::SsoLinksControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper
  include OidcHelper

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @user = link_to_sso(users(:reader))
    2.times { Session.start(user: @user, method: "sso", user_agent: nil, ip_address: nil) }
    put_mail_state(:working)
  end

  def sign_in_manager
    managers = AccessControl::Group.create!(name: "User managers")
    %w[users.manage].each { |key| AccessControl::Grant.create!(group: managers, permission: key, scope: {}) }
    AccessControl::Membership.create!(user: users(:editor_branch), group: managers)
    sign_in_as(users(:editor_branch))
  end

  test "an owner unlinks, the person is signed out everywhere and the mail is queued" do
    sign_in_as users(:one)
    own = Current.session

    get "/cs-studio/users/#{@user.id}/edit"
    assert_select "[data-sso-badge]", text: "Signs in with id.example.com"
    assert_select "[data-zone=sso] button", text: "Unlink…"

    assert_enqueued_emails 1 do
      delete "/cs-studio/users/#{@user.id}/sso_link"
    end

    assert_redirected_to "/cs-studio/users/#{@user.id}/edit"
    assert_equal 303, response.status
    assert_not @user.reload.sso_linked?
    assert_empty @user.sessions
    assert Audit::Event.exists?(action: "sso.unlinked", subject: @user)
    # The actor's own session is untouched: only an owner sees the zone and owners never link.
    assert Session.exists?(own.id)
    follow_redirect!
    assert_includes response.body, "reader@example.com is unlinked from id.example.com. A mail to set a password is on its way."
    assert_select "[data-sso-badge]", count: 0
    assert_select "[data-zone=sso]", count: 0
  end

  test "without mail the dialog and the toast promise no mail, and none is queued" do
    put_mail_state(:not_set_up)
    sign_in_as users(:one)

    get "/cs-studio/users/#{@user.id}/edit"
    assert_includes CGI.unescapeHTML(response.body), "Mail isn't set up, so they get no mail to set a password until it is."
    assert_not_includes response.body, "They get a mail to set a password here."

    assert_no_enqueued_emails do
      delete "/cs-studio/users/#{@user.id}/sso_link"
    end
    assert_not @user.reload.sso_linked?
    follow_redirect!
    assert_includes CGI.unescapeHTML(response.body), "reader@example.com is unlinked from id.example.com. Mail isn't set up, so no mail was sent: set up mail, then ask them to request a password reset."
    assert_not_includes response.body, "A mail to set a password is on its way."
  end

  test "an admin who is no owner is refused and nothing changes" do
    sign_in_manager

    get "/cs-studio/users/#{@user.id}/edit"
    assert_select "[data-zone=sso]", count: 0
    assert_select "[data-sso-badge]", count: 1

    assert_no_enqueued_emails do
      delete "/cs-studio/users/#{@user.id}/sso_link"
    end

    assert_response :forbidden
    assert_equal 1, Audit::Event.where(action: "access.denied", subject_type: "User", subject_id: @user.id).count
    assert @user.reload.sso_linked?
    assert_equal 2, @user.sessions.count
  end

  test "an unlinked user shows no zone and no badge, and unlinking one is a refusal toast" do
    sign_in_as users(:one)
    other = users(:author)

    get "/cs-studio/users/#{other.id}/edit"
    assert_select "[data-zone=sso]", count: 0
    assert_select "[data-sso-badge]", count: 0

    delete "/cs-studio/users/#{other.id}/sso_link"
    assert_redirected_to "/cs-studio/users/#{other.id}/edit"
    assert flash[:alert].present?
  end

  test "with single sign-on on, the badge and the zone use the provider's name" do
    with_sso do
      sign_in_as users(:one)
      get "/cs-studio/users/#{@user.id}/edit"
      assert_select "[data-sso-badge]", text: "Signs in with #{OidcHelper::NAME}"
    end
  end

  test "an unknown user is a 404" do
    sign_in_as users(:one)
    delete "/cs-studio/users/0/sso_link"
    assert_response :not_found
  end
end
