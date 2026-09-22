require "test_helper"

# Avo::Actions::RegenerateApiToken's own logic is covered directly in
# test/models/regenerate_api_token_action_test.rb; this is the wiring --
# does the ApiToken resource page still render with the action, the new
# `user` field, and the usage-tracking fields registered.
class AvoApiTokensTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "admin@example.com", password: "password123")
    sign_in_as(@user)
  end

  test "the api tokens index renders, including the standalone regenerate action" do
    get "/avo/resources/api_tokens"

    assert_response :success
    assert_includes response.body, "Regenerate my API token"
  end

  test "an existing token's show page renders its user and usage tracking fields" do
    token, = ApiToken.generate!(@user)
    token.record_usage!("203.0.113.5")

    get "/avo/resources/api_tokens/#{token.id}"

    assert_response :success
    assert_includes response.body, @user.email_address
    assert_includes response.body, "203.0.113.5"
  end
end
