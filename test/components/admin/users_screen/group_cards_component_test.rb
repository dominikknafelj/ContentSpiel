require "test_helper"

class Admin::UsersScreen::GroupCardsComponentTest < ViewComponent::TestCase
  def cards(selected:, assignable:, manage: false, frame: true)
    groups = AccessControl::Group.order(:name).to_a
    with_request_url("/cs-studio/users/1/edit") do
      render_inline Admin::UsersScreen::GroupCardsComponent.new(groups: groups, selected_ids: selected, assignable_ids: assignable, manage_groups: manage, frame: frame)
    end
  end

  def ids = AccessControl::Group.pluck(:id)

  # The tile's look, the selection's outline included, is `.admin-tile`'s
  # (content-spiel.tailwind.css): the checkbox stands as the label's own
  # child, so `.admin-tile:has(> input:checked)` follows the box with no
  # script, and the label carries no edge or tint of its own.
  test "a group is a tile whose checkbox is its label's, ticked drawn by the tile's selected rule" do
    editor = access_control_groups(:editor)
    cards(selected: [ editor.id ], assignable: ids)

    assert_selector "input[type=hidden][name='user[group_ids][]'][value='']", visible: :all, count: 1
    assert_selector "label[for='user_group_ids_#{editor.id}']", count: 1
    assert_selector "label.admin-tile.grid[data-group-card='#{editor.id}']", text: "Editor"
    assert_selector "label[data-group-card='#{editor.id}']", text: "Full, unscoped access to posts and pages, plus tags and media."
    assert_selector "label[data-group-card='#{editor.id}'] > input[type=checkbox][name='user[group_ids][]'][value='#{editor.id}'][checked]"
    assert_selector "label.admin-tile > input[type=checkbox]:not([checked])", minimum: 1
    page.all("label[data-group-card]").each do |tile|
      classes = tile[:class].split
      assert_empty classes.grep(/\A(?:rounded-cs|border|border-line|bg-sunken|bg-surface)\z|has-\[/), "the tile draws its look from .admin-tile, not from #{tile[:class]}"
    end
    assert_no_selector "label[data-locked]"
    assert_no_text "You can't grant this group."
  end

  test "a group the viewer can't grant is a sunken tile with its reason, and a ticked one is carried by a hidden input" do
    locked = access_control_groups(:admin)
    cards(selected: [ locked.id, access_control_groups(:read_only).id ], assignable: ids - [ locked.id ])

    assert_selector "label.admin-tile[data-group-card='#{locked.id}'][data-locked]", text: "You can't grant this group."
    assert_selector "label[data-group-card='#{locked.id}'] > input[type=checkbox][checked][disabled]"
    assert_selector "label[data-group-card='#{locked.id}'] input[type=hidden][name='user[group_ids][]'][value='#{locked.id}']", visible: :all, count: 1
    # An open tile carries nothing extra: its own box posts.
    assert_no_selector "label[data-group-card='#{access_control_groups(:read_only).id}'] input[type=hidden]", visible: :all
    assert_selector "label[data-locked]", count: 1
  end

  test "an unticked group the viewer can't grant is locked but not carried" do
    locked = access_control_groups(:admin)
    cards(selected: [], assignable: ids - [ locked.id ])

    assert_selector "label[data-group-card='#{locked.id}'][data-locked] input[type=checkbox][disabled]:not([checked])"
    assert_no_selector "label[data-group-card='#{locked.id}'] input[type=hidden]", visible: :all
  end

  test "on the editor it is the Groups card, with Manage groups at the head's end for a groups.manage holder only" do
    cards(selected: [], assignable: ids, manage: true)
    assert_selector "section.admin-settings-card.admin-user-groups[aria-labelledby='user-groups-title']" do
      assert_selector ".admin-settings-card__head h2#user-groups-title", text: "Groups"
      assert_selector ".admin-settings-card__end a[href='/cs-studio/groups']", text: "Manage groups →"
      assert_selector "label.admin-tile", count: AccessControl::Group.count
    end
    assert_equal Admin::Ui::ButtonComponent.classes(:tertiary, size: :small).split.sort, page.find("a", text: "Manage groups →")[:class].split.sort

    cards(selected: [], assignable: ids, manage: false)
    assert_no_selector "a", text: "Manage groups"
  end

  test "in a dialog it draws no card frame" do
    cards(selected: [], assignable: ids, frame: false)

    assert_no_selector ".admin-settings-card"
    assert_selector "[role=group][aria-labelledby='user-groups-title']" do
      assert_selector "#user-groups-title", text: "Groups"
      assert_selector "label.admin-tile", count: AccessControl::Group.count
    end
    assert_selector "input[type=hidden][name='user[group_ids][]'][value='']", visible: :all, count: 1
  end
end
