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
      assert_equal [ "You don't have permission to give a token that group" ], refused.errors
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
      assert_equal [ "You don't have permission to give a token that group" ], refused.errors

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

  # A removed content type's name is dormant, not gone: a group that still
  # stores one is judged as stored, so a token can't be bound to it by (or for)
  # someone who couldn't grant that name.
  def blog_holder(extra = [])
    holders = AccessControl::Group.create!(name: "Blog holders")
    AccessControl::Grant.create!(group: holders, permission: "posts.edit", scope: { "content_types" => %w[blog] })
    extra.each { |key| AccessControl::Grant.create!(group: holders, permission: key, scope: {}) }
    AccessControl::Membership.create!(user: users(:editor_branch), group: holders)
    users(:editor_branch)
  end

  def group_carrying(types)
    AccessControl::Group.create!(name: "Carrying").tap do |group|
      AccessControl::Grant.create!(group: group, permission: "posts.edit", scope: { "content_types" => types })
    end
  end

  [ %w[blog retired_type], %w[retired_type] ].each do |types|
    test "a token can't be bound to a group storing #{types.inspect} by a user who could only grant blog" do
      holder = blog_holder
      carrying = group_carrying(types)

      assert_difference -> { Audit::Event.where(action: "access.denied").sum(:occurrences) }, 1 do
        refused = as(holder) { ApiTokens::Issue.call(holder, group: carrying) }
        assert refused.denied?
        assert_equal [ "You don't have permission to give a token that group" ], refused.errors
      end
      assert_empty holder.api_tokens
    end
  end

  test "issuing someone else's token for a group storing a removed type needs both the user and the actor to cover the name" do
    carrying = group_carrying(%w[blog retired_type])
    manager = blog_holder(%w[tokens.manage])
    unscoped = AccessControl::Group.create!(name: "Unscoped editors")
    AccessControl::Grant.create!(group: unscoped, permission: "posts.edit", scope: {})
    AccessControl::Membership.create!(user: users(:reader), group: unscoped)

    # The token's user could grant it (unscoped), the actor couldn't.
    refused = as(manager) { ApiTokens::Issue.call(users(:reader), group: carrying) }
    assert refused.denied?
    # The actor could (an owner), the token's user couldn't.
    refused = as_owner { ApiTokens::Issue.call(manager, group: carrying) }
    assert refused.denied?
    assert_empty ApiToken.where(group: carrying)

    assert as(users(:reader)) { ApiTokens::Issue.call(users(:reader), group: carrying) }.ok?, "an unscoped holder's own token"
    assert as_owner { ApiTokens::Issue.call(users(:one), group: carrying) }.ok?, "an owner's own token"
    assert ApiTokens::Issue.call(manager, group: carrying, actor: nil).ok?, "a trusted code path chooses freely"
  end

  test "no name picks the next free Token N, and the event records the name" do
    token, = ApiTokens::Issue.call(users(:one), group: access_control_groups(:read_only)).record
    assert_match(/\AToken \d+\z/, token.name)
    assert_equal token.name, Audit::Event.where(action: "token.issued", subject_id: token.id).last.metadata["name"]
  end

  test "a given name is used and recorded" do
    token, = ApiTokens::Issue.call(users(:one), group: access_control_groups(:read_only), name: "  Claude desktop ").record
    assert_equal "Claude desktop", token.name
    assert_equal "Claude desktop", Audit::Event.where(action: "token.issued", subject_id: token.id).last.metadata["name"]
  end

  test "a blank name is refused with no token and no event" do
    assert_no_difference [ "ApiToken.count", "Audit::Event.count" ] do
      result = ApiTokens::Issue.call(users(:one), group: access_control_groups(:read_only), name: "")
      assert_not result.ok?
      assert_includes result.errors, "Name can't be blank"
    end
  end

  test "a duplicate active name is refused" do
    ApiTokens::Issue.call(users(:one), group: access_control_groups(:read_only), name: "Claude")
    assert_no_difference "ApiToken.count" do
      assert_not ApiTokens::Issue.call(users(:one), group: access_control_groups(:read_only), name: "claude").ok?
    end
  end

  test "losing the unique-name race is an ordinary failure, with no token and no event" do
    group = access_control_groups(:read_only)
    original = ApiToken.method(:generate!)
    # Forces the race: after the service's own pre-check has passed, a
    # duplicate active token appears (validation skipped) just before its write.
    ApiToken.define_singleton_method(:generate!) do |user, **options|
      ApiToken.new(user:, group: options[:group], name: options[:name], token_digest: "x").save!(validate: false)
      original.call(user, **options)
    end

    # (The forced duplicate is written inside the service's own transaction,
    # so it rolls back with it: the net is no token and no event.)
    assert_no_difference [ "Audit::Event.count", "ApiToken.count" ] do
      begin
        result = ApiTokens::Issue.call(users(:one), group:, name: "Claude")
        assert_not result.ok?
        assert_includes result.errors.to_sentence, "already the name of one of this user's active tokens"
      end
    end
  ensure
    ApiToken.define_singleton_method(:generate!, original)
  end

  # Final fix wave (Task 2): the rescue is for ONE thing, the name race. Any
  # other failure of the insert must not be reported as "that name is taken".
  test "a failed insert that isn't the name race is not reported as a name clash" do
    group = access_control_groups(:read_only)

    with_singleton_override(ApiToken, :generate!, ->(user, **) { ApiToken.new(user:, name: "Claude").tap(&:save!) }) do
      result = ApiTokens::Issue.call(users(:one), group:, name: "Claude")

      assert_not result.ok?
      assert_no_match(/already the name/, result.errors.to_sentence)
      assert_match(/Group must exist/, result.errors.to_sentence)
    end

    with_singleton_override(ApiToken, :generate!, ->(*, **) { raise ActiveRecord::RecordNotUnique, 'duplicate key value violates unique constraint "some_other_index"' }) do
      assert_raises(ActiveRecord::RecordNotUnique) { ApiTokens::Issue.call(users(:one), group:, name: "Claude") }
    end
  end

  # Final fix wave (S-M6): the create endpoint is open to every signed-in user
  # and looks the group up by a raw id, so a refusal that named the group let
  # anyone read every group's name by counting ids upwards.
  test "the refusal for a group the user can't assign doesn't name it" do
    as(users(:author)) do
      refused = ApiTokens::Issue.call(users(:author), group: access_control_groups(:admin), name: "forged")

      assert refused.denied?
      assert_no_match(/Admin/, refused.errors.to_sentence)
    end
  end
end
