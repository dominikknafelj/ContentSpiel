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

  test "short names a user without a name by the part of the address before the at sign" do
    render_inline(Admin::Ui::UserNameComponent.new(user: users(:one), short: true))
    assert_text "one"
    assert_no_text "example.com"

    user = users(:one)
    user.name = "Ada Lovelace"
    render_inline(Admin::Ui::UserNameComponent.new(user: user, short: true))
    assert_text "Ada Lovelace"
  end

  test "short leaves a deleted user and no user at all as they are" do
    render_inline(Admin::Ui::UserNameComponent.new(user: nil, user_id: 999_999, short: true))
    assert_text "a deleted user"
    render_inline(Admin::Ui::UserNameComponent.new(user: nil, short: true))
    assert_text "System"
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
