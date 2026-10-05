require "test_helper"

class Users::SaveTest < ActiveSupport::TestCase
  test "a blank password leaves the password alone" do
    user = users(:one)
    result = Users::Save.call(user, attributes: { email_address: "new@example.com", password: "", password_confirmation: "" }, actor: nil)

    assert result.ok?, result.errors.to_sentence
    assert user.reload.authenticate("password")
  end

  test "a password with a matching confirmation is changed" do
    user = users(:one)
    result = Users::Save.call(user, attributes: { password: "new-password-1", password_confirmation: "new-password-1" }, actor: nil)

    assert result.ok?, result.errors.to_sentence
    assert user.reload.authenticate("new-password-1")
  end

  # Final fix wave (C, P17): `has_secure_password` only compares the
  # confirmation when it's non-nil, and a form that omits it (or a caller
  # that forgets it) would otherwise set the password unconfirmed.
  test "a password without a confirmation is refused" do
    user = users(:one)
    [ { password: "new-password-1" }, { password: "new-password-1", password_confirmation: "" } ].each do |attributes|
      result = Users::Save.call(user, attributes: attributes, actor: nil)

      assert_not result.ok?
      assert_includes result.errors, "Password confirmation can't be blank"
      assert user.reload.authenticate("password")
    end
  end

  test "a new user needs a confirmation too" do
    result = Users::Save.call(attributes: { email_address: "fresh@example.com", password: "new-password-1" }, actor: nil)

    assert_not result.ok?
    assert_not User.exists?(email_address: "fresh@example.com")
  end

  # --- Groups and owner (access-control design spec §3.3 "Users", Task 8) ------

  test "a user's groups are saved and recorded in user.updated" do
    user = users(:reader)
    groups = [ access_control_groups(:author), access_control_groups(:read_only) ]

    result = as_owner { Users::Save.call(user, attributes: { group_ids: [ "", *groups.map(&:id) ] }) }

    assert result.ok?, result.errors.inspect
    assert_equal groups.map(&:id).sort, user.reload.group_ids.sort
    event = Audit::Event.find_by!(action: "user.updated", subject: user)
    assert_equal [ [ access_control_groups(:read_only).id ], groups.map(&:id).sort ], event.field_changes["group_ids"]
    assert_equal groups.map(&:id).sort, event.snapshot["group_ids"]
  end

  test "a non-owner can't add someone to a group holding permissions they lack" do
    managers = AccessControl::Group.create!(name: "User managers")
    AccessControl::Grant.create!(group: managers, permission: "users.manage", scope: {})
    # Enough to manage the reader at all (their Read only group, fix round 1 I1).
    AccessControl::Grant.create!(group: managers, permission: "posts.read", scope: {})
    AccessControl::Grant.create!(group: managers, permission: "pages.read", scope: {})
    AccessControl::Membership.create!(user: users(:editor_branch), group: managers)

    result = as(users(:editor_branch)) do
      Users::Save.call(users(:reader), attributes: { group_ids: [ access_control_groups(:admin).id ] })
    end

    assert result.denied?
    assert_equal [ "You don't have permission to add users to the Admin group" ], result.errors
    assert_equal [ access_control_groups(:read_only).id ], users(:reader).reload.group_ids
  end

  # A removed content type's name is dormant, not gone: a group that still
  # stores one is judged as stored, so someone who could only grant "blog"
  # can't put a user into it, take one out of it, or manage a user who is in it.
  def manager_holding(posts_edit_scope)
    managers = AccessControl::Group.create!(name: "User managers")
    %w[users.manage posts.read pages.read].each { |key| AccessControl::Grant.create!(group: managers, permission: key, scope: {}) }
    AccessControl::Grant.create!(group: managers, permission: "posts.edit", scope: posts_edit_scope)
    AccessControl::Membership.create!(user: users(:editor_branch), group: managers)
    users(:editor_branch)
  end

  def group_carrying(scope)
    AccessControl::Group.create!(name: "Carrying").tap { |group| AccessControl::Grant.create!(group: group, permission: "posts.edit", scope: scope) }
  end

  [ %w[blog retired_type], %w[retired_type] ].each do |types|
    test "a non-owner who could only grant blog can't add a user to a group storing #{types.inspect}: one access.denied" do
      manager = manager_holding({ "content_types" => %w[blog] })
      carrying = group_carrying({ "content_types" => types })

      assert_difference -> { Audit::Event.where(action: "access.denied").sum(:occurrences) }, 1 do
        result = as(manager) { Users::Save.call(users(:reader), attributes: { group_ids: [ access_control_groups(:read_only).id, carrying.id ] }) }
        assert result.denied?
        assert_equal [ "You don't have permission to add users to the Carrying group" ], result.errors
      end
      assert_equal [ access_control_groups(:read_only).id ], users(:reader).reload.group_ids
      assert_empty Audit::Event.where(action: "user.updated")
    end

    test "a user who is in a group storing #{types.inspect} is outranked for a non-owner who could only grant blog" do
      manager = manager_holding({ "content_types" => %w[blog] })
      carrying = group_carrying({ "content_types" => types })
      AccessControl::Membership.create!(user: users(:reader), group: carrying)

      assert_equal :outranked, Users::Manageability.for(manager, users(:reader), channel: :admin)
      [ { name: "Renamed" }, { group_ids: [ access_control_groups(:read_only).id ] } ].each do |attributes|
        result = as(manager) { Users::Save.call(users(:reader), attributes: attributes) }
        assert result.denied?, attributes.inspect
      end
      assert as(manager) { Users::Destroy.call(users(:reader)) }.denied?, "deleting them is managing them too"
      assert_nil users(:reader).reload.name
      assert_includes users(:reader).group_ids, carrying.id
    end
  end

  test "an unscoped holder, a holder whose grant names the removed type, and an owner may add a user to such a group" do
    carrying = group_carrying({ "content_types" => %w[blog retired_type] })
    ids = [ access_control_groups(:read_only).id, carrying.id ].sort

    manager = manager_holding({})
    assert_equal :editable, Users::Manageability.for(manager, users(:reader), channel: :admin)
    result = as(manager) { Users::Save.call(users(:reader), attributes: { group_ids: ids }) }
    assert result.ok?, result.errors.inspect
    assert_equal ids, users(:reader).reload.group_ids.sort
    assert_equal :editable, Users::Manageability.for(manager, users(:reader), channel: :admin)

    AccessControl::Grant.find_by!(group: manager.groups.find_by!(name: "User managers"), permission: "posts.edit").update!(scope: { "content_types" => %w[blog retired_type] })
    AccessControl::ActorGrants.reset!
    result = as(manager) { Users::Save.call(users(:reader), attributes: { group_ids: [ access_control_groups(:read_only).id ] }) }
    assert result.ok?, result.errors.inspect

    result = as_owner { Users::Save.call(users(:reader), attributes: { group_ids: ids }) }
    assert result.ok?, result.errors.inspect
  end

  test "a token's group bounds it for a removed type too, even an owner's" do
    carrying = group_carrying({ "content_types" => %w[blog retired_type] })
    token_group = AccessControl::Group.create!(name: "Token managers")
    %w[users.manage posts.read pages.read].each { |key| AccessControl::Grant.create!(group: token_group, permission: key, scope: {}) }
    AccessControl::Grant.create!(group: token_group, permission: "posts.edit", scope: { "content_types" => %w[blog] })
    token, = ApiToken.generate!(users(:one), group: token_group)

    result = as(token, channel: :mcp) { Users::Save.call(users(:reader), attributes: { group_ids: [ access_control_groups(:read_only).id, carrying.id ] }) }

    assert result.denied?
    assert_equal [ access_control_groups(:read_only).id ], users(:reader).reload.group_ids
  end

  test "only an owner may change owner" do
    result = as(users(:two)) { Users::Save.call(users(:reader), attributes: { owner: "1" }) }
    assert result.denied?
    assert_equal [ "Only an owner can change who is an owner" ], result.errors
    assert_not users(:reader).reload.owner?

    # An unchanged value (the form's hidden "0") isn't a change.
    assert as(users(:two)) { Users::Save.call(users(:reader), attributes: { owner: "0", email_address: "r@example.com" }) }.ok?
  end

  test "an owner promotes a user, recorded as user.owner_changed" do
    result = as_owner { Users::Save.call(users(:reader), attributes: { owner: "1" }) }

    assert result.ok?, result.errors.inspect
    assert users(:reader).reload.owner?
    event = Audit::Event.find_by!(action: "user.owner_changed", subject: users(:reader))
    assert_equal({ "owner" => [ false, true ] }, event.field_changes)
    assert_not Audit::Event.exists?(action: "user.updated", subject: users(:reader))
  end

  test "the last owner can't be demoted" do
    result = as_owner { Users::Save.call(users(:one), attributes: { owner: "0" }) }

    assert_not result.ok?
    assert_includes result.errors.to_sentence, "can't demote the last owner"
    assert users(:one).reload.owner?
  end
  # --- Final fix wave (Important 2, Minor 1) ------------------------------------

  test "a non-owner can't remove a user from a group beyond their rights" do
    managers = AccessControl::Group.create!(name: "User managers")
    %w[users.manage posts.read pages.read].each do |key|
      AccessControl::Grant.create!(group: managers, permission: key, scope: {})
    end
    AccessControl::Membership.create!(user: users(:editor_branch), group: managers)
    AccessControl::Membership.create!(user: users(:reader), group: managers)

    # The reader's own groups are within the actor's rights, so removing
    # them is fine...
    ok = as(users(:editor_branch)) { Users::Save.call(users(:reader), attributes: { group_ids: [ managers.id ] }) }
    assert ok.ok?, ok.errors.inspect

    # ...but taking the Admin member out of Admin isn't.
    refused = as(users(:editor_branch)) { Users::Save.call(users(:two), attributes: { group_ids: [] }) }
    assert refused.denied?
    assert_includes users(:two).reload.group_ids, access_control_groups(:admin).id
  end

  test "an owner's token is judged on its group: no owner flags, no groups beyond it" do
    token_group = AccessControl::Group.create!(name: "User managers")
    %w[users.manage posts.read pages.read].each do |key|
      AccessControl::Grant.create!(group: token_group, permission: key, scope: {})
    end
    token, = ApiToken.generate!(users(:one), group: token_group)

    as(token, channel: :mcp) do
      promote = Users::Save.call(users(:reader), attributes: { owner: "1" })
      assert promote.denied?
      assert_equal [ "Only an owner can change who is an owner" ], promote.errors

      owners_account = Users::Save.call(users(:one), attributes: { email_address: "taken@example.com" })
      assert owners_account.denied?

      beyond = Users::Save.call(users(:reader), attributes: { group_ids: [ access_control_groups(:admin).id ] })
      assert beyond.denied?
      assert_equal [ "You don't have permission to add users to the Admin group" ], beyond.errors

      outranked = Users::Save.call(users(:two), attributes: { email_address: "two-new@example.com" })
      assert outranked.denied?
    end

    assert_not users(:reader).reload.owner?
    assert_equal "one@example.com", users(:one).reload.email_address
    assert_equal [ access_control_groups(:read_only).id ], users(:reader).group_ids
  end

  test "saves a name and records it in the event's field changes" do
    actor = users(:one)
    result = Users::Save.call(users(:two), attributes: { name: "Grace Hopper" }, actor: actor)
    assert result.ok?, result.errors.to_sentence
    assert_equal "Grace Hopper", users(:two).reload.name
    assert_equal [ nil, "Grace Hopper" ], Audit::Event.order(:id).last.field_changes["name"]
  end

  # --- A password change ends that user's sessions ---------------------------
  #
  # Someone who changes a password does it because the old one is, or may
  # be, in the wrong hands -- and whoever holds it may already be signed in.

  test "changing another user's password ends every session of that user" do
    user = users(:reader)
    2.times { user.sessions.create! }
    bystander = users(:author).sessions.create!

    result = as(users(:one)) { Users::Save.call(user, attributes: { password: "new-password-1", password_confirmation: "new-password-1" }) }

    assert result.ok?, result.errors.to_sentence
    assert_empty user.sessions.reload
    assert Session.exists?(bystander.id)
  end

  test "changing anything but the password leaves the user's sessions alone" do
    user = users(:reader)
    session = user.sessions.create!

    result = as(users(:one)) do
      Users::Save.call(user, attributes: { name: "A new name", email_address: "renamed@example.com",
        password: "", password_confirmation: "", group_ids: [ AccessControl::Group.find_by!(name: "Editor").id ] })
    end

    assert result.ok?, result.errors.to_sentence
    assert_equal "A new name", user.reload.name
    assert Session.exists?(session.id)
  end

  test "changing your own password in the Users module keeps the session you act in and ends the others" do
    owner = users(:one)
    current = owner.sessions.create!
    other = owner.sessions.create!

    result = Current.set(session: current) do
      as(owner) { Users::Save.call(owner, attributes: { password: "new-password-1", password_confirmation: "new-password-1" }) }
    end

    assert result.ok?, result.errors.to_sentence
    assert Session.exists?(current.id)
    assert_not Session.exists?(other.id)
  end

  test "a refused password change ends no session" do
    user = users(:reader)
    session = user.sessions.create!

    result = as(users(:one)) { Users::Save.call(user, attributes: { password: "new-password-1", password_confirmation: "something else" }) }

    assert_not result.ok?
    assert Session.exists?(session.id)
  end

  test "changing only the groups moves the user's updated_at and each gained or lost group's" do
    user = users(:author)
    gained = access_control_groups(:read_only)
    lost = access_control_groups(:author)
    [ user, gained, lost, access_control_groups(:editor) ].each { |record| record.update_columns(updated_at: 1.hour.ago) }

    result = Users::Save.call(user, attributes: { group_ids: [ gained.id ] }, actor: nil)

    assert result.ok?, result.errors.to_sentence
    assert_operator user.reload.updated_at, :>, 30.minutes.ago
    assert_operator gained.reload.updated_at, :>, 30.minutes.ago
    assert_operator lost.reload.updated_at, :>, 30.minutes.ago
    assert_operator access_control_groups(:editor).reload.updated_at, :<, 30.minutes.ago, "a group that is neither gained nor lost stays put"
  end
end
