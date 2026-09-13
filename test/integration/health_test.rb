require "test_helper"

class HealthTest < ActionDispatch::IntegrationTest
  test "GET /up returns success" do
    get "/up"
    assert_response :success
  end
end
