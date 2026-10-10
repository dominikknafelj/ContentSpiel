require "test_helper"

class Admin::Ui::UserNameComponentTest < ViewComponent::TestCase
  test "a user reads as their display name" do
    user = users(:one)
    user.name = "Ada Lovelace"
    render_inline(Admin::Ui::UserNameComponent.new(user: user))
    assert_text "Ada Lovelace"
  end

  test "a user without a name reads as their email" do
    render_inline(Admin::Ui::UserNameComponent.new(user: users(:one)))
    assert_text "one@example.com"
  end

  test "a user id with no surviving user reads as a deleted user" do
    render_inline(Admin::Ui::UserNameComponent.new(user: nil, user_id: 999_999))
    assert_text "a deleted user"
  end

  test "no user at all reads as System" do
    render_inline(Admin::Ui::UserNameComponent.new(user: nil))
    assert_text "System"
  end
end
