require "test_helper"

class Admin::GroupsScreen::ListComponentTest < ViewComponent::TestCase
  test "the list is a table: a group's row is one stretched link ending in Edit, Built-in a badge, a zero count in meta" do
    groups = AccessControl::Group.order(:name).to_a
    custom = AccessControl::Group.create!(name: "Zebras", description: "Striped")
    row = "tr#access_control_group_#{custom.id}"

    render_inline Admin::GroupsScreen::ListComponent.new(groups: groups + [ custom ], member_counts: { custom.id => 3 }, token_counts: {})

    assert_equal [ "Group", "Members", "Tokens", "Actions" ], page.all("thead th[scope=col]").map { |th| th.text(:all).strip }
    assert_selector "thead tr.border-line-strong.text-label.text-meta"
    assert_selector "thead th span.sr-only", text: "Actions", visible: :all
    assert_selector "tbody tr", count: groups.size + 1
    assert_selector "#{row} a", count: 1
    assert_selector "#{row} th[scope=row] a.admin-row-link", text: "Zebras"
    assert_selector "#{row} th[scope=row] .text-small.text-dim", text: "Striped"
    assert_selector "#{row} [data-column=members].text-small.text-ink", text: "3 members"
    assert_selector "#{row} [data-column=tokens].text-small.text-meta", text: "0 tokens"
    assert_selector "#{row} td:last-child .admin-row-verb[aria-hidden=true]", text: "Edit"
    assert_no_selector "#{row}", text: "Built-in"
    built_in = groups.find(&:built_in?)
    assert_selector "tr#access_control_group_#{built_in.id} th[scope=row] span.rounded-cs.bg-sunken.text-label", text: "Built-in"
    assert_no_selector "button"
    assert_no_selector "li"
    assert_selector "p.text-small.text-meta", text: "Built-in groups can be changed but not deleted."
  end
end
