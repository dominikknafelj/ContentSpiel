require "test_helper"

class Users::UpdateProfileTest < ActiveSupport::TestCase
  test "a user changes their own name, audited as user.updated" do
    user = users(:two)
    Current.set(actor: user, channel: :admin) do
      result = Users::UpdateProfile.call(user, name: "Grace Hopper")
      assert result.ok?
    end
    assert_equal "Grace Hopper", user.reload.name
    assert_equal "user.updated", Audit::Event.order(:id).last.action
    assert_equal [ nil, "Grace Hopper" ], Audit::Event.order(:id).last.field_changes["name"]
  end

  test "changing someone else's name is refused and logged as a denial" do
    actor, other = users(:two), users(:one)
    Current.set(actor: actor, channel: :admin) do
      assert_not Users::UpdateProfile.call(other, name: "Mallory").ok?
    end
    assert_nil other.reload.name
    assert_equal "access.denied", Audit::Event.order(:id).last.action
  end

  test "a user with a short legacy password can still change their name" do
    user = users(:two) # fixture digest is for the 8-character "password"
    Current.set(actor: user, channel: :admin) do
      assert Users::UpdateProfile.call(user, name: "Still Fine").ok?
    end
  end

  test "a too-long name fails without an event" do
    user = users(:two)
    before = Audit::Event.count
    Current.set(actor: user, channel: :admin) do
      assert_not Users::UpdateProfile.call(user, name: "a" * 121).ok?
    end
    assert_equal before, Audit::Event.count
  end
end
