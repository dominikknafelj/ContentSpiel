require "test_helper"

# `Users::Manageability.for` (round 3 Task 12, D17): the one answer the user
# editor draws its read-only states from and the services enforce. Besides
# the three answers, the nil trusted actor, a token and yourself, the PARITY
# test below holds the predicate to the services over every actor and target
# pair: whatever `Users::Save` refuses on these grounds (and nothing else), it
# reports as not `:editable`, with the matching refusal.
class Users::ManageabilityTest < ActiveSupport::TestCase
  OWNER_ONLY = "You don't have permission to change an owner's account".freeze
  OUTRANKED = "You don't have permission to manage users".freeze

  def manager_group
    @manager_group ||= AccessControl::Group.create!(name: "User managers").tap do |group|
      %w[users.manage posts.read pages.read].each { |key| AccessControl::Grant.create!(group: group, permission: key, scope: {}) }
    end
  end

  def manager
    @manager ||= users(:editor_branch).tap { |user| AccessControl::Membership.create!(user: user, group: manager_group) }
  end

  test "an owner target is protected from a non-owner, editable for an owner" do
    assert_equal :owner_protected, Users::Manageability.for(manager, users(:one), channel: :admin)
    assert_equal :owner_protected, Users::Manageability.for(users(:two), users(:one), channel: :admin)
    assert_equal :editable, Users::Manageability.for(users(:one), users(:one), channel: :admin)
  end

  test "a user holding a group the actor can't manage is outranked" do
    assert_equal :outranked, Users::Manageability.for(manager, users(:two), channel: :admin)
    assert_equal :editable, Users::Manageability.for(manager, users(:reader), channel: :admin)
  end

  test "owner protection is checked before outranking" do
    admin_owner = User.create!(email_address: "ao@example.com", password: "password12345", owner: true)
    AccessControl::Membership.create!(user: admin_owner, group: access_control_groups(:admin))
    assert_equal :owner_protected, Users::Manageability.for(manager, admin_owner, channel: :admin)
  end

  test "a user being created and a user with no groups are editable" do
    assert_equal :editable, Users::Manageability.for(manager, User.new, channel: :admin)
    assert_equal :editable, Users::Manageability.for(manager, User.create!(email_address: "n@example.com", password: "password12345"), channel: :admin)
  end

  test "a nil actor is trusted on the trusted channels and on none" do
    [ nil, :setup, :console, :system ].each do |channel|
      assert_equal :editable, Users::Manageability.for(nil, users(:one), channel: channel), channel.inspect
      assert_equal :editable, Users::Manageability.for(nil, users(:two), channel: channel), channel.inspect
    end
    %i[admin mcp public].each do |channel|
      assert_equal :owner_protected, Users::Manageability.for(nil, users(:one), channel: channel), channel.to_s
      assert_equal :editable, Users::Manageability.for(nil, users(:two), channel: channel), "a nil actor is never outranked, the services deny it earlier (#{channel})"
    end
  end

  test "the channel defaults to Current.channel" do
    as(nil, channel: :admin) { assert_equal :owner_protected, Users::Manageability.for(nil, users(:one)) }
    as(nil, channel: :console) { assert_equal :editable, Users::Manageability.for(nil, users(:one)) }
  end

  test "an API token is never an owner, and is judged on its group and its user" do
    owners_token, = ApiToken.generate!(users(:one), group: manager_group)
    assert_equal :owner_protected, Users::Manageability.for(owners_token, users(:one), channel: :mcp)
    assert_equal :outranked, Users::Manageability.for(owners_token, users(:two), channel: :mcp)
    assert_equal :editable, Users::Manageability.for(owners_token, users(:reader), channel: :mcp)

    own, = ApiToken.generate!(manager, group: manager_group)
    assert_equal :editable, Users::Manageability.for(own, manager, channel: :mcp), "a token's own user is never outranked"
  end

  test "yourself is never outranked" do
    assert_equal :editable, Users::Manageability.for(manager, manager, channel: :admin)
    assert_equal :editable, Users::Manageability.for(users(:one), users(:one), channel: :admin)
  end

  test "the last owner is still editable: that is a different rule, kept on User" do
    assert_equal :editable, Users::Manageability.for(users(:one), users(:one), channel: :admin)
  end

  # The services refuse on these grounds ONLY where `users.manage` itself
  # holds, so that is where the two are compared.
  test "agrees with Users::Save for every actor and target" do
    token_of_owner, = ApiToken.generate!(users(:one), group: manager_group)
    token_of_manager, = ApiToken.generate!(manager, group: manager_group)
    second_owner = User.create!(email_address: "owner2@example.com", password: "password12345", owner: true)
    mixed = User.create!(email_address: "mixed@example.com", password: "password12345").tap do |user|
      AccessControl::Membership.create!(user: user, group: access_control_groups(:read_only))
      AccessControl::Membership.create!(user: user, group: access_control_groups(:admin))
    end
    actors = { owner: [ users(:one), :admin ], admin_member: [ users(:two), :admin ], manager: [ manager, :admin ],
               reader: [ users(:reader), :admin ], owner_token: [ token_of_owner, :mcp ], manager_token: [ token_of_manager, :mcp ],
               trusted: [ nil, :console ], untrusted_nil: [ nil, :admin ] }
    targets = [ users(:one), second_owner, users(:two), users(:reader), users(:author), manager, mixed ]

    checked = 0
    actors.each do |label, (actor, channel)|
      targets.each do |target|
        as(actor, channel: channel) do
          answer = Users::Manageability.for(actor, target)
          result = Users::Save.call(User.find(target.id), attributes: { name: "Parity" }, actor: actor)
          holds_manage = AccessControl.allowed?(actor, "users.manage", target)
          message = "#{label} -> #{target.email_address}: #{answer}, #{result.errors.inspect}"

          if !holds_manage
            assert result.denied?, message
          else
            expected = { editable: [], owner_protected: [ OWNER_ONLY ], outranked: [ OUTRANKED ] }.fetch(answer)
            assert_equal expected, (result.ok? ? [] : result.errors), message
          end
          checked += 1
        end
      end
    end
    assert_equal actors.size * targets.size, checked
  end
end
