require "test_helper"

class Admin::UsersScreen::ListComponentTest < ViewComponent::TestCase
  def list(users, last: {}, current: users(:one))
    with_request_url("/cs-studio/users") do
      render_inline Admin::UsersScreen::ListComponent.new(users: users, last_sign_ins: last, current_user: current)
    end
  end

  test "a row is one stretched link: avatar initial, name over email, (you), OWNER, group chips and last sign-in" do
    users(:two).update!(name: "Tara Two")
    list(User.includes(:groups).order(:email_address).to_a, last: { users(:two).id => 3.days.ago })

    assert_selector "li", count: User.count
    assert_selector "li#user_#{users(:two).id} a", count: 1, text: "Tara Two"
    assert_selector "li#user_#{users(:two).id} a[class*='after:absolute'][class*='after:inset-0']"
    assert_selector "li#user_#{users(:two).id} [aria-hidden=true]", text: "T"
    assert_selector "li#user_#{users(:two).id} span", text: "two@example.com"
    assert_selector "li#user_#{users(:two).id} [data-column=groups] span", text: "Admin"
    assert_selector "li#user_#{users(:two).id} [data-column=last-sign-in] time", text: "3d ago"
    assert_selector "li#user_#{users(:one).id}", text: "(you)"
    assert_selector "li#user_#{users(:one).id}", text: "Owner"
    assert_selector "li#user_#{users(:one).id} [data-column=groups]", text: "No groups"
    assert_selector "li#user_#{users(:one).id} [data-column=last-sign-in]", text: "Never"
    assert_no_selector "li#user_#{users(:two).id}", text: "Owner"
    assert_no_selector "li#user_#{users(:two).id}", text: "(you)"
    assert_no_selector "button"
  end

  test "a user without a name shows the email once" do
    list([ users(:reader) ])
    assert_selector "li a", text: "reader@example.com"
    assert_selector "li", text: /reader@example.com/, count: 1
  end
end
