require "test_helper"

class Users::DestroyTest < ActiveSupport::TestCase
  test "deletes a user when another remains" do
    users(:one)
    result = Users::Destroy.call(users(:two), actor: nil)

    assert result.ok?, result.errors.to_sentence
    assert_not User.exists?(users(:two).id)
  end

  test "refuses to delete the last owner" do
    last = users(:one)

    result = Users::Destroy.call(last, actor: nil)

    assert_not result.ok?
    assert_equal [ "The last owner can't be deleted" ], result.errors
    assert User.exists?(last.id)
  end
  # Final fix wave (Minor 5): a deleted user's tokens are revoked through
  # `ApiTokens::Revoke` first, so the log says which assistants stopped
  # working and why -- also for an actor with users.manage but not
  # tokens.manage.
  test "deleting a user revokes their active tokens, one token.revoked each, before user.deleted" do
    managers = AccessControl::Group.create!(name: "User managers")
    %w[users.manage posts.read pages.read].each do |key|
      AccessControl::Grant.create!(group: managers, permission: key, scope: {})
    end
    AccessControl::Membership.create!(user: users(:editor_branch), group: managers)
    reader = users(:reader)
    first, = ApiToken.generate!(reader, group: access_control_groups(:read_only))
    second, = ApiToken.generate!(reader, group: access_control_groups(:read_only))
    old, = ApiToken.generate!(reader, group: access_control_groups(:read_only))
    old.revoke!

    result = as(users(:editor_branch)) { Users::Destroy.call(reader) }

    assert result.ok?, result.errors.inspect
    revoked = Audit::Event.where(action: "token.revoked").order(:id)
    assert_equal [ first.id, second.id ].sort, revoked.pluck(:subject_id).sort
    assert(revoked.all? { |event| event.metadata == { "reason" => "user deleted" } })
    assert_operator revoked.last.id, :<, Audit::Event.find_by!(action: "user.deleted").id
    assert_equal 0, ApiToken.where(user_id: reader.id).count
  end

  test "a refused delete leaves the tokens active and logs no revocation" do
    token, = ApiToken.generate!(users(:one), group: access_control_groups(:admin))

    result = Users::Destroy.call(users(:one), actor: nil)

    assert_not result.ok?
    assert_nil token.reload.revoked_at
    assert_not Audit::Event.exists?(action: "token.revoked")
  end
end
