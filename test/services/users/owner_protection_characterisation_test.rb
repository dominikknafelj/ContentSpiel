require "test_helper"

# Round 3 Task 12: `Users::OwnerProtection`'s predicates (`owner_protected?`,
# `outranked?`, `actor_owner?`) move into `Users::Manageability` so the
# services and the user editor's read-only states can't drift. These tests
# were written, and passed, BEFORE the move, against the services alone: they
# pin who the services refuse and who they let through, for the cases the
# extraction could most easily loosen -- a trusted nil actor, an API token, the
# actor's own account, an owner target, the last owner. They stay as the
# regression net; `manageability_test.rb` asks the same questions of the new
# predicate and requires the two to agree.
class Users::OwnerProtectionCharacterisationTest < ActiveSupport::TestCase
  OWNER_ONLY = "You don't have permission to change an owner's account".freeze

  def user_manager_group
    @user_manager_group ||= AccessControl::Group.create!(name: "User managers").tap do |group|
      %w[users.manage posts.read pages.read].each { |key| AccessControl::Grant.create!(group: group, permission: key, scope: {}) }
    end
  end

  def user_manager
    @user_manager ||= users(:editor_branch).tap { |user| AccessControl::Membership.create!(user: user, group: user_manager_group) }
  end

  def rename(user, actor: Current.actor)
    Users::Save.call(user, attributes: { name: "Renamed" }, actor: actor)
  end

  # --- A nil actor is trusted on the trusted channels only ------------------

  test "a nil actor on a trusted channel (or none) may change an owner and an outranking-group member" do
    [ nil, :setup, :console, :system ].each do |channel|
      as(nil, channel: channel) do
        assert rename(users(:one)).ok?, "owner target, channel #{channel.inspect}"
        assert rename(users(:two)).ok?, "admin member target, channel #{channel.inspect}"
      end
    end
  end

  test "a nil actor on :admin or :mcp is denied everything, an owner target included" do
    %i[admin mcp public].each do |channel|
      as(nil, channel: channel) do
        assert rename(users(:one)).denied?, "owner target, channel #{channel}"
        assert rename(users(:two)).denied?, "admin member target, channel #{channel}"
        assert rename(users(:reader)).denied?, "reader target, channel #{channel}"
      end
    end
    assert_nil users(:one).reload.name
  end

  # --- A non-owner and an owner target ---------------------------------------

  test "a non-owner users.manage holder is refused an owner's account with the owner-only message" do
    as(user_manager) do
      refused = rename(users(:one))
      assert refused.denied?
      assert_equal [ OWNER_ONLY ], refused.errors

      assert Users::Destroy.call(users(:one)).denied?
      assert Users::UpdatePassword.call(users(:one), password: "taken-over-1", password_confirmation: "taken-over-1").denied?
    end
    assert users(:one).reload.authenticate("password")
  end

  test "an owner may change another owner" do
    other = User.create!(email_address: "owner2@example.com", password: "password12345", owner: true)
    as_owner do
      assert rename(other).ok?
      assert_equal "Renamed", other.reload.name
    end
  end

  # --- Outranked: a group the actor can't manage -----------------------------

  test "a non-owner is refused a user holding a group they can't manage, and allowed one whose groups they can" do
    as(user_manager) do
      refused = rename(users(:two))
      assert refused.denied?
      assert_equal [ "You don't have permission to manage users" ], refused.errors

      assert rename(users(:reader)).ok?
      # A user holding no group at all is within anyone's rights.
      assert rename(User.create!(email_address: "nogroup@example.com", password: "password12345")).ok?
    end
  end

  test "a user holding one manageable group and one that outranks the actor is outranked" do
    mixed = users(:reader)
    AccessControl::Membership.create!(user: mixed, group: access_control_groups(:admin))
    as(user_manager) { assert rename(mixed).denied? }
  end

  test "an owner and a trusted actor are never outranked" do
    as_owner { assert rename(users(:two)).ok? }
    as(nil, channel: :console) { assert rename(users(:two)).ok? }
  end

  # --- Yourself ---------------------------------------------------------------

  test "acting on yourself is never outranked, and never owner-protected for an owner" do
    as(user_manager) { assert rename(user_manager).ok? }
    as_owner { assert rename(users(:one)).ok? }
  end

  test "an admin member may manage another admin member and themselves" do
    other_admin = User.create!(email_address: "admin2@example.com", password: "password12345")
    AccessControl::Membership.create!(user: other_admin, group: access_control_groups(:admin))
    as(users(:two)) do
      assert rename(other_admin).ok?
      assert rename(users(:two)).ok?
    end
  end

  # --- An API token ------------------------------------------------------------

  test "an owner's token is never an owner: an owner target and the owner flag are refused" do
    token, = ApiToken.generate!(users(:one), group: user_manager_group)
    as(token, channel: :mcp) do
      refused = rename(users(:one))
      assert refused.denied?
      assert_equal [ OWNER_ONLY ], refused.errors
      assert Users::Destroy.call(users(:one)).denied?

      promote = Users::Save.call(users(:reader), attributes: { owner: "1" })
      assert_equal [ "Only an owner can change who is an owner" ], promote.errors
    end
  end

  test "a token is judged on group and user together: outranked by its group's rights, not its user's" do
    token, = ApiToken.generate!(users(:one), group: user_manager_group)
    as(token, channel: :mcp) do
      assert rename(users(:two)).denied?, "the token's group can't manage Admin even though its user is an owner"
      assert rename(users(:reader)).ok?
    end
  end

  test "a token acting on its own user is never outranked" do
    token, = ApiToken.generate!(user_manager, group: user_manager_group)
    as(token, channel: :mcp) { assert rename(user_manager).ok? }
  end

  # --- The last owner -----------------------------------------------------------

  test "the only owner can neither be demoted nor deleted, by themselves or anyone allowed to try" do
    as_owner do
      demote = Users::Save.call(users(:one), attributes: { owner: "0" })
      assert_not demote.ok?
      assert_includes demote.errors.to_sentence, "can't demote the last owner"

      # The refused demotion left the object's owner flag assigned in memory; the actor is that object.
      users(:one).reload
      destroy = Users::Destroy.call(users(:one))
      assert_not destroy.ok?
      assert_includes destroy.errors.to_sentence, "The last owner can't be deleted"
    end
    assert users(:one).reload.owner?
  end

  test "an owner may demote themselves while another owner remains" do
    other = User.create!(email_address: "owner2@example.com", password: "password12345", owner: true)
    as(users(:one)) do
      result = Users::Save.call(users(:one), attributes: { owner: "0" })
      assert result.ok?, result.errors.inspect
    end
    assert_not users(:one).reload.owner?
    assert other.reload.owner?
    assert Audit::Event.exists?(action: "user.owner_changed", subject: users(:one))
  end
end
