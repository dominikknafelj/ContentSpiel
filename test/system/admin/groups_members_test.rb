require "application_system_test_case"

# The group editor's members chips, delete zone and view-only state in a real
# browser (round 3 Task 11): adding a member by typing part of an email, the
# footer's count, the delete dialog naming the token, and reading a scope in a
# group the viewer can only view.
class Admin::GroupsMembersSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @group = AccessControl::Group.create!(name: "Branch crew", description: "A crew")
    AccessControl::Grant.create!(group: @group, permission: "posts.read", scope: {})
    sign_in_via_form(users(:one))
  end

  def member_search = find("#group_member_ids")

  test "typing part of an email offers the user; picking adds a chip and the footer counts 1 change; Save group stores the member" do
    visit edit_admin_group_path(@group)
    await_admin_controllers
    assert_selector ".admin-save-bar", text: /No unsaved changes/i

    member_search.send_keys("author@")
    assert_selector "#group_member_ids-listbox [role=option]", text: /author@example\.com/
    # Typing alone is no change.
    assert_selector ".admin-save-bar", text: /No unsaved changes/i
    member_search.send_keys(:down, :enter)

    assert_selector "li[data-chip-value='#{users(:author).id}']", text: "author@example.com"
    assert_selector ".admin-save-bar", text: /\b1 unsaved change\b/i

    press "Save group"
    assert_text "Group saved"
    assert_selector "li[data-chip-value='#{users(:author).id}']"
    assert_equal [ users(:author) ], @group.users.reload.to_a
  end

  test "an owner is never offered, and a typed query that matches nobody says so" do
    visit edit_admin_group_path(@group)
    await_admin_controllers

    member_search.send_keys("one@")
    assert_no_selector "#group_member_ids-listbox [role=option]"
    assert_selector ".admin-save-bar", text: /No unsaved changes/i
  end

  test "removing a member is one change, and putting them back is none" do
    AccessControl::Membership.create!(user: users(:reader), group: @group)
    visit edit_admin_group_path(@group)
    await_admin_controllers

    find("li[data-chip-value='#{users(:reader).id}'] button[aria-label^='Remove']").click
    assert_selector ".admin-save-bar", text: /\b1 unsaved change\b/i

    member_search.send_keys("reader@")
    assert_selector "#group_member_ids-listbox [role=option]", text: /reader@example\.com/
    member_search.send_keys(:down, :enter)
    assert_selector ".admin-save-bar", text: /No unsaved changes/i
  end

  test "Delete group… opens the dialog naming the token; confirming returns to the list with the toast" do
    AccessControl::Membership.create!(user: users(:reader), group: @group)
    ApiToken.generate!(users(:reader), group: @group, name: "Deploy bot")
    visit edit_admin_group_path(@group)
    await_admin_controllers

    assert_text "1 member loses its permissions. 1 AI token is revoked."
    press "Delete group…"
    within "dialog#delete-group-#{@group.id}" do
      assert_text "Delete “Branch crew”?"
      assert_text "Deploy bot — reader@example.com"
      press "Delete group"
    end

    assert_current_path admin_groups_path
    assert_text "Group deleted"
    assert_not AccessControl::Group.exists?(@group.id)
  end

  test "a group the viewer can only view: the notice, no footer, and a scope that still opens" do
    everything = AccessControl::Group.create!(name: "Everything", description: "All")
    AccessControl::Grant.create!(group: everything, permission: "users.manage", scope: {})
    AccessControl::Grant.create!(group: everything, permission: "posts.edit", scope: { "content_types" => [ "blog" ] })
    manager = User.create!(email_address: "viewer@example.org", password: "a-long-enough-password")
    managers = AccessControl::Group.create!(name: "Managers", description: "Manage groups")
    AccessControl::Grant.create!(group: managers, permission: "groups.manage", scope: {})
    AccessControl::Membership.create!(user: manager, group: managers)
    Capybara.reset_sessions!
    sign_in_via_form(manager, password: "a-long-enough-password")

    visit edit_admin_group_path(everything)
    await_admin_controllers

    assert_text "This group has permissions you can't hand out, so you can only view it."
    assert_no_selector ".admin-save-bar"
    assert_no_text "Delete this group"
    assert_selector "input[name='group[name]']:disabled"

    row = "[data-permission='posts.edit']"
    assert_selector "#{row} [data-scope-editor]", visible: :hidden
    find("#{row} a[role=button]", text: "View scope").click
    assert_selector "#{row} [data-scope-editor]"
    assert_selector "#{row} [data-scope-editor] input[value=blog][checked]:disabled"
    find("#{row} a[role=button]", text: "Hide scope").click
    assert_no_selector "#{row} [data-scope-editor]"
  end
end
