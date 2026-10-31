require "test_helper"

class InvitationsControllerTest < ActionDispatch::IntegrationTest
  test "the invitation page answers the expired sentence, signed out and never cached" do
    get admin_invitation_path

    assert_response :success
    assert_includes response.body, "This invite has expired. Ask the person who invited you to send a new one."
    assert_includes response.headers["Cache-Control"], "no-store"
  end
end
