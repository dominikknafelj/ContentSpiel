require "test_helper"

class Admin::GroupsScreen::ListComponentTest < ViewComponent::TestCase
  test "one stretched link per row, counts in their columns, the built-in tag and the line below" do
    groups = AccessControl::Group.order(:name).to_a
    custom = AccessControl::Group.create!(name: "Zebras", description: "Striped")

    render_inline Admin::GroupsScreen::ListComponent.new(groups: groups + [ custom ], member_counts: { custom.id => 3 }, token_counts: { custom.id => 1 })

    assert_selector "li", count: groups.size + 1
    assert_selector "li#access_control_group_#{custom.id} a", count: 1, text: "Zebras"
    assert_selector "li#access_control_group_#{custom.id} a[class*='after:absolute'][class*='after:inset-0']"
    assert_selector "li#access_control_group_#{custom.id} [data-column=members]", text: "3 members"
    assert_selector "li#access_control_group_#{custom.id} [data-column=tokens]", text: "1 token"
    assert_selector "li#access_control_group_#{custom.id}", text: "Striped"
    assert_no_selector "li#access_control_group_#{custom.id}", text: "Built-in"
    assert_selector "li", text: "Built-in", minimum: 1
    assert_no_selector "button"
    assert_text "Built-in groups can be changed but not deleted."
  end
end
