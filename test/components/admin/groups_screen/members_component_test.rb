require "test_helper"

# The group editor's Members chips (round 3 Task 11).
class Admin::GroupsScreen::MembersComponentTest < ViewComponent::TestCase
  def render_members(users)
    render_inline Admin::GroupsScreen::MembersComponent.new(users: users, search_url: "/cs-studio/users/suggest")
  end

  test "a chip per member: the display name, the email as the hint, a tracked hidden input; the blank sentinel ahead of them" do
    users(:reader).update_columns(name: "Rita Reader")
    render_members([ users(:reader), users(:author) ])

    assert_selector "li[data-chip-value='#{users(:reader).id}']", text: /Rita Reader\s*·\s*reader@example.com/
    assert_selector "li[data-chip-value='#{users(:author).id}'] [data-chip-hint]", count: 0, visible: :all
    assert_selector "input[type=hidden][name='group[member_ids][]'][data-save-bar-track]", count: 3, visible: :all # sentinel + 2 chips
    assert_selector "input[type=hidden][name='group[member_ids][]'][value='']", count: 1, visible: :all
    assert_selector "input[role=combobox]:not([name])"
  end

  test "an owner member is a chip like any other, marked Owner" do
    render_members([ users(:one) ])

    assert_selector "li[data-chip-value='#{users(:one).id}']", text: /Owner/
    assert_selector "li[data-chip-value='#{users(:one).id}'] input[type=hidden][value='#{users(:one).id}']", visible: :all
  end

  test "the help line says why owners aren't offered, and the search points at the suggest endpoint" do
    render_members([])

    assert_text "Owners aren't listed: they already have every permission."
    assert_selector "[data-admin--chip-input-search-url-value='/cs-studio/users/suggest']"
    assert_selector "[data-admin--chip-input-create-value='false']"
  end
end
