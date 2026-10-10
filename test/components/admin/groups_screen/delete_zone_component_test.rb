require "test_helper"

# The group editor's delete zone (round 3 Task 11, handoff C37).
class Admin::GroupsScreen::DeleteZoneComponentTest < ViewComponent::TestCase
  def zone(group, members: 2, tokens: [])
    with_request_url("/cs-studio/groups/#{group.id}/edit") do
      render_inline Admin::GroupsScreen::DeleteZoneComponent.new(group: group, member_count: members, tokens: tokens)
    end
  end

  def token(name, user)
    ApiToken.generate!(user, group: AccessControl::Group.find_by!(name: "Admin"), name: name)[0]
  end

  test "a custom group: the effect in words, a danger-text trigger, and the dialog with the solid danger confirm" do
    group = AccessControl::Group.create!(name: "Bots")
    zone(group, members: 2, tokens: [ token("Deploy", users(:reader)) ])

    assert_selector "h2", text: "Delete this group"
    assert_text "2 members lose its permissions. 1 AI token is revoked."
    assert_selector "button[data-action='admin--ui--dialog#open'][data-admin--ui--dialog-id-param='delete-group-#{group.id}']", text: "Delete group…"
    assert_selector "dialog#delete-group-#{group.id}", visible: :all do
      assert_selector "form[action='/cs-studio/groups/#{group.id}'] input[name=_method][value=delete]", visible: :all
    end
    assert_selector "dialog button[type=submit]", text: "Delete group", visible: :all
    assert_selector "dialog p", text: "Its 2 members lose these permissions, and its 1 AI token is revoked. Users themselves are not deleted.", visible: :all
    assert_selector "dialog li", text: "Deploy — reader@example.com", visible: :all
  end

  test "a built-in group shows the note instead: no trigger, no dialog" do
    zone(access_control_groups(:editor))

    assert_text "A built-in group can be changed but not deleted."
    assert_no_selector "button"
    assert_no_selector "dialog", visible: :all
  end

  test "the wording for one member, none and no tokens" do
    group = AccessControl::Group.create!(name: "Quiet")
    zone(group, members: 1)
    assert_text "1 member loses its permissions. It has no AI tokens."
    assert_selector "dialog p", text: "Its 1 member loses these permissions. Users themselves are not deleted.", visible: :all

    zone(group, members: 0)
    assert_text "It has no members. It has no AI tokens."
  end
end
