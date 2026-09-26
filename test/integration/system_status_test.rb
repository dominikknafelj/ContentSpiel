require "test_helper"

class SystemStatusTest < ActionDispatch::IntegrationTest
  test "an unauthenticated request cannot reach the system status page" do
    get "/avo/system_status"

    assert_response :redirect
  end

  test "the system status page shows the same checks as the setup wizard" do
    sign_in_as(users(:one))

    get "/avo/system_status"

    assert_response :success
    assert_includes response.body, "File storage"
    assert_includes response.body, "Background jobs"
  end
end
