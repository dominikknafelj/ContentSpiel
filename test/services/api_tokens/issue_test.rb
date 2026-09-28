require "test_helper"

class ApiTokens::IssueTest < ActiveSupport::TestCase
  test "issues a token whose raw value authenticates" do
    result = ApiTokens::Issue.call(users(:one), group: access_control_groups(:read_only))
    token, raw = result.record
    assert result.ok?
    assert_equal token, ApiToken.authenticate(raw)
  end

  test "issuing again adds another active token rather than replacing the old one" do
    old, old_raw = ApiTokens::Issue.call(users(:one), group: access_control_groups(:read_only)).record
    ApiTokens::Issue.call(users(:one), group: access_control_groups(:read_only))
    assert_nil old.reload.revoked_at
    assert_equal old, ApiToken.authenticate(old_raw)
  end

  test "revoke stops a token authenticating" do
    token, raw = ApiTokens::Issue.call(users(:one), group: access_control_groups(:read_only)).record
    assert ApiTokens::Revoke.call(token).ok?
    assert_nil ApiToken.authenticate(raw)
  end

  # Access-control design spec §3.3 "Tokens", Review Focus 1.
  test "a user may only give a token a group whose every grant they hold" do
    as(users(:author)) do
      assert ApiTokens::Issue.call(users(:author), group: access_control_groups(:author)).ok?
      assert ApiTokens::Issue.call(users(:author), group: access_control_groups(:read_only)).ok?

      refused = ApiTokens::Issue.call(users(:author), group: access_control_groups(:admin))
      assert refused.denied?
      assert_equal [ "You don't have permission to give a token the Admin group" ], refused.errors
    end
    assert_equal 2, users(:author).api_tokens.count
  end

  test "a group is required" do
    result = as(users(:author)) { ApiTokens::Issue.call(users(:author), group: nil) }

    assert_not result.ok?
    assert_equal [ "Choose a group for the token" ], result.errors
  end
  # Final fix wave (Minor 2): issuing for someone else, the group must be
  # within the *actor's* rights too, not only the token user's.
  test "issuing someone else's token needs the group to be within the actor's rights" do
    managers = AccessControl::Group.create!(name: "Token managers")
    %w[tokens.manage posts.read pages.read].each do |key|
      AccessControl::Grant.create!(group: managers, permission: key, scope: {})
    end
    AccessControl::Membership.create!(user: users(:editor_branch), group: managers)

    as(users(:editor_branch)) do
      refused = ApiTokens::Issue.call(users(:two), group: access_control_groups(:admin))
      assert refused.denied?
      assert_equal [ "You don't have permission to give a token the Admin group" ], refused.errors

      assert ApiTokens::Issue.call(users(:two), group: access_control_groups(:read_only)).ok?
    end
    assert_equal [ access_control_groups(:read_only).id ], users(:two).api_tokens.pluck(:group_id)
  end

  # Final fix wave (Minor 1): a token minting tokens is judged on its own
  # group, even an owner's.
  test "an owner's token can't mint a token with a group beyond its own" do
    token_group = AccessControl::Group.create!(name: "Token managers")
    %w[tokens.manage posts.read pages.read].each do |key|
      AccessControl::Grant.create!(group: token_group, permission: key, scope: {})
    end
    token, = ApiToken.generate!(users(:one), group: token_group)

    result = as(token, channel: :mcp) { ApiTokens::Issue.call(users(:one), group: access_control_groups(:admin)) }

    assert result.denied?
    assert_equal 1, users(:one).api_tokens.count
  end
end
