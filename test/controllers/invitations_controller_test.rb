require "test_helper"

class InvitationsControllerTest < ActionDispatch::IntegrationTest
  test "the invitation page answers the expired sentence, signed out and never cached" do
    get admin_invitation_path

    assert_response :success
    assert_includes response.body, "This invite has expired. Ask the person who invited you to send a new one."
    assert_includes response.headers["Cache-Control"], "no-store"
  end

  test "an invitation refuses a leaked password and draws the form again" do
    invitation = open_invitation("dana@example.com", name: "Dana")
    token = invitation.generate_token_for(:accept)

    with_leaked_password_check(leaked: [ "correct horse battery" ]) do
      assert_no_difference "User.count" do
        post admin_accept_invitation_path, params: { token: token, name: "Dana", password: "correct horse battery", password_confirmation: "correct horse battery" }
      end
    end

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /#{Regexp.escape("This password is in a list of leaked passwords, so it isn't safe to use. Choose another one.")}/
    assert_select "input[type=hidden][name=token]" do |fields|
      assert_equal token, fields.first["value"]
    end
    assert_not_includes response.body, "correct horse battery"
    assert invitation.reload.open?
  end
end
