require "test_helper"

class Admin::UsersScreen::ListComponentTest < ViewComponent::TestCase
  def list(users, last: {}, current: users(:one), invitations: [])
    with_request_url("/cs-studio/users") do
      render_inline Admin::UsersScreen::ListComponent.new(users: users, invitations: invitations, last_sign_ins: last, current_user: current)
    end
  end

  # The classes of the circle in `row`, and those the shared avatar draws at
  # `:md` in `tone`.
  def circle(row) = page.find("#{row} th[scope=row] span[aria-hidden=true].rounded-full")["class"].split.sort
  def avatar(tone) = Admin::Ui::AvatarComponent.new(initials: "x", size: :md, tone: tone).then { |component| render_inline(component).at_css("span")["class"].split.sort }

  test "the list is a table with scoped headers, and a user's row is one stretched link ending in Edit" do
    users(:two).update!(name: "Tara Two")
    list(User.includes(:groups).order(:email_address).to_a, last: { users(:two).id => 3.days.ago })

    assert_selector "div.rounded-card.bg-surface.shadow-1 > div.admin-table-scroll--x > table.admin-users-list.admin-card-table.w-full"
    assert_equal [ "User", "Groups", "Last sign-in", "Actions" ], page.all("thead th[scope=col]").map { |th| th.text(:all).strip }
    assert_selector "thead th[scope=col] span.sr-only", text: "Actions"
    assert_selector "tbody tr", count: User.count

    row = "tr#user_#{users(:two).id}"
    assert_selector "#{row} th[scope=row] a.admin-row-link", count: 1, text: "Tara Two"
    assert_selector "#{row} a", count: 1
    assert_selector "#{row} th[scope=row]", text: "two@example.com"
    assert_selector "#{row} [data-column=last-sign-in] time", text: "3d ago"
    assert_selector "#{row} td:last-child span.admin-row-verb", text: "Edit"
    assert_selector "tr#user_#{users(:one).id}", text: "(you)"
    assert_selector "tr#user_#{users(:one).id} th[scope=row]", text: "Owner"
    assert_selector "tr#user_#{users(:one).id} [data-column=last-sign-in]", text: "Never"
    assert_no_selector row, text: "Owner"
    assert_no_selector row, text: "(you)"
    assert_no_selector "button"
  end

  test "a user's circle is the shared avatar, your own in the own tone and everyone else's, an invitation's too, in the other tone" do
    users(:two).update!(name: "Tara Two")
    dana = open_invitation("dana@example.com")
    own, other = avatar(:own), avatar(:other)
    list([ users(:one), users(:two) ], invitations: [ dana ])

    assert_equal own, circle("tr#user_#{users(:one).id}")
    assert_equal other, circle("tr#user_#{users(:two).id}")
    assert_equal other, circle("tr#invitation_#{dana.id}")
    assert_selector "tr#user_#{users(:two).id} th[scope=row] span[aria-hidden=true]", exact_text: "TT"
    assert_selector "tr#invitation_#{dana.id} th[scope=row] span[aria-hidden=true]", exact_text: "da"
    assert_selector "tr#invitation_#{dana.id} [data-invite-state=open]", text: "Invited"
  end

  test "groups are badges, and none reads No groups" do
    list([ users(:one), users(:two), users(:reader) ])

    badge = ".rounded-cs.text-label.bg-sunken"
    assert_selector "tr#user_#{users(:two).id} [data-column=groups] span#{badge}", text: "Admin"
    assert_selector "tr#user_#{users(:reader).id} [data-column=groups] span#{badge}", text: "Read only"
    assert_selector "tr#user_#{users(:one).id} [data-column=groups]", text: "No groups"
    assert_no_selector "tr#user_#{users(:one).id} [data-column=groups] span#{badge}"
  end

  test "an invitation's row opens no editor: its name is text, and its menu stands over the row" do
    dana = open_invitation("dana@example.com")
    list([ users(:one) ], invitations: [ dana ])

    assert_selector "tr#invitation_#{dana.id}[data-invited] th[scope=row] span.font-medium", text: "dana@example.com"
    assert_no_selector "tr#invitation_#{dana.id} a"
    assert_no_selector "tr#invitation_#{dana.id} .admin-row-verb"
    assert_selector "tr#invitation_#{dana.id} td:last-child .relative.z-\\(--cs-z-raised\\)[data-invite-menu] button[aria-label='Actions for dana@example.com']"
  end

  test "a user without a name shows the email once" do
    list([ users(:reader) ])
    assert_selector "tbody tr a", text: "reader@example.com"
    assert_equal 1, page.find("tbody tr").text.scan("reader@example.com").size
  end
end
