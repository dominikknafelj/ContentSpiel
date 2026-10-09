require "test_helper"

class Admin::DashboardScreen::CardComponentTest < ViewComponent::TestCase
  test "caps its rows at five and links on with the arrow" do
    render_inline Admin::DashboardScreen::CardComponent.new(title: "Your drafts", id: "d", empty: "None", link: [ "/cs-studio/posts?status=draft", "All drafts" ]) do |card|
      8.times { |i| card.with_row { "Row #{i}" } }
    end

    assert_selector "section[aria-labelledby=d] h2#d", text: "Your drafts"
    assert_selector "li", count: 5
    assert_no_text "Row 5"
    assert_selector "a[href='/cs-studio/posts?status=draft'][aria-label='All drafts']", text: "→"
  end

  test "an explicit limit raises the cap" do
    render_inline Admin::DashboardScreen::CardComponent.new(title: "Recent activity", id: "a", empty: "None", limit: 15) do |card|
      8.times { |i| card.with_row { "Row #{i}" } }
    end

    assert_selector "li", count: 8
  end

  test "empty shows its sentence in the card, no arrow without a link, and the hint when given" do
    render_inline Admin::DashboardScreen::CardComponent.new(title: "Going live next", id: "g", empty: "Nothing scheduled.", hint: "Schedule a draft to see it here.")

    assert_text "Nothing scheduled."
    assert_text "Schedule a draft to see it here."
    assert_no_selector "a"
    assert_no_selector "li"
  end

  # The notes cards' header extras (notes spec §5): a count beside the title
  # and an action before the arrow. A card without them has neither wrapper's
  # content.
  test "a badge stands beside the title and an action before the arrow" do
    render_inline Admin::DashboardScreen::CardComponent.new(title: "Notes for you", id: "n", empty: "None", link: [ "/cs-studio/notes", "All notes for you" ]) do |card|
      card.with_badge { "3 new" }
      card.with_action { "Mark all read" }
    end

    assert_selector "header > div:first-child", text: /Notes for you\s*3 new\s*\z/
    assert_selector "header", text: /Notes for you\s*3 new\s*Mark all read\s*→/
  end
end
