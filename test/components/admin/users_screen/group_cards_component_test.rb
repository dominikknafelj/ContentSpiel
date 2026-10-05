require "test_helper"

class Admin::UsersScreen::GroupCardsComponentTest < ViewComponent::TestCase
  def cards(selected:, assignable:, manage: false)
    groups = AccessControl::Group.order(:name).to_a
    with_request_url("/cs-studio/users/1/edit") do
      render_inline Admin::UsersScreen::GroupCardsComponent.new(groups: groups, selected_ids: selected, assignable_ids: assignable, manage_groups: manage)
    end
  end

  def ids = AccessControl::Group.pluck(:id)

  test "a card is the label: a real checkbox named user[group_ids][], the name and the description, after a blank sentinel" do
    cards(selected: [ access_control_groups(:editor).id ], assignable: ids)

    assert_selector "input[type=hidden][name='user[group_ids][]'][value='']", visible: :all, count: 1
    assert_selector "label[for='user_group_ids_#{access_control_groups(:editor).id}']", count: 1
    assert_selector "label[data-group-card='#{access_control_groups(:editor).id}']", text: "Editor"
    assert_selector "label[data-group-card='#{access_control_groups(:editor).id}']", text: "Full, unscoped access to posts and pages, plus tags and media."
    assert_selector "label[data-group-card='#{access_control_groups(:editor).id}'] input[type=checkbox][name='user[group_ids][]'][checked]"
    assert_selector "label[data-group-card='#{access_control_groups(:editor).id}'][class*='has-[:checked]:bg-accent-tint']"
    assert_selector "label[data-group-card='#{access_control_groups(:editor).id}'].grid"
    assert_no_selector "label[data-locked]"
    assert_no_text "You can't grant this group."
  end

  test "a ticked group the viewer can't grant is a sunken card with a greyed ticked box, carried by a hidden input" do
    locked = access_control_groups(:admin)
    cards(selected: [ locked.id, access_control_groups(:read_only).id ], assignable: ids - [ locked.id ])

    assert_selector "label[data-group-card='#{locked.id}'][data-locked][class*='bg-sunken']", text: "You can't grant this group."
    assert_selector "label[data-group-card='#{locked.id}'] input[type=checkbox][checked][disabled]"
    assert_selector "label[data-group-card='#{locked.id}'] input[type=hidden][name='user[group_ids][]'][value='#{locked.id}']", visible: :all, count: 1
    # An open card carries nothing extra: its own box posts.
    assert_no_selector "label[data-group-card='#{access_control_groups(:read_only).id}'] input[type=hidden]", visible: :all
  end

  test "an unticked group the viewer can't grant is locked but not carried" do
    locked = access_control_groups(:admin)
    cards(selected: [], assignable: ids - [ locked.id ])

    assert_selector "label[data-group-card='#{locked.id}'][data-locked] input[type=checkbox][disabled]:not([checked])"
    assert_no_selector "label[data-group-card='#{locked.id}'] input[type=hidden]", visible: :all
  end

  test "Manage groups is a link for a groups.manage holder only" do
    cards(selected: [], assignable: ids, manage: true)
    assert_selector "a[href='/cs-studio/groups']", text: "Manage groups →"

    cards(selected: [], assignable: ids, manage: false)
    assert_no_selector "a", text: "Manage groups"
  end
end
