require "test_helper"

# Avo::Actions::RegenerateApiToken's own core logic (app/avo/actions/regenerate_api_token.rb)
# -- exercised directly rather than through Avo's action-dispatch HTTP
# endpoint, which is Avo's own well-tested machinery, not this app's. The
# resource-page smoke test below (does the page still render with this
# action registered) covers the wiring; this covers what the action does.
class RegenerateApiTokenActionTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "admin@example.com", password: "password123")
  end

  test "mints a token bound to current_user and reports the raw value" do
    action = Avo::Actions::RegenerateApiToken.new(user: @user)

    assert_difference "@user.api_tokens.count", 1 do
      action.handle(current_user: @user)
    end

    message = action.response[:messages].first
    raw_token = message[:body].delete_prefix("New token: ")
    assert_equal @user.api_tokens.order(:created_at).last, ApiToken.authenticate(raw_token)
  end

  # "Regenerate," not "add another": a stray active token from a previous run
  # would otherwise keep authenticating after this one supposedly replaced it.
  test "revokes the user's existing active tokens before minting a new one" do
    action = Avo::Actions::RegenerateApiToken.new(user: @user)
    old_token, old_raw = ApiToken.generate!(@user)

    action.handle(current_user: @user)

    assert_not_nil old_token.reload.revoked_at
    assert_nil ApiToken.authenticate(old_raw)
  end

  test "does not touch another user's tokens" do
    other_user = User.create!(email_address: "other@example.com", password: "password123")
    _other_token, other_raw = ApiToken.generate!(other_user)
    action = Avo::Actions::RegenerateApiToken.new(user: @user)

    action.handle(current_user: @user)

    assert_equal other_user, ApiToken.authenticate(other_raw)&.user
  end
end
