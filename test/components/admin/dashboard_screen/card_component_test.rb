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

  # Layout points spec, decision 12 and Claude Design's O6: an empty card says
  # one line in dim, left-aligned where its first row would be, with its
  # action (if any) after it. No centred bold title, no 48px of padding.
  test "an empty card says one line where its first row would be, in dim, with its action after it" do
    render_inline Admin::DashboardScreen::CardComponent.new(title: "Your drafts", id: "d", empty: "No drafts.") do |card|
      card.with_empty_action { '<a href="#x">Start a draft</a>'.html_safe }
    end

    assert_selector "section > header + p[data-card-empty].px-4.text-sm.text-dim", text: /\ANo drafts\.\s+Start a draft\z/
    assert_selector "p[data-card-empty] a[href='#x']", text: "Start a draft"
    assert_no_selector ".admin-empty-state, h3, ul"
  end

  test "an empty card without an action says its line alone, and a card with rows draws neither" do
    render_inline Admin::DashboardScreen::CardComponent.new(title: "Going live next", id: "g", empty: "Nothing scheduled.")
    assert_selector "p[data-card-empty]", exact_text: "Nothing scheduled."
    assert_no_selector "a"

    render_inline Admin::DashboardScreen::CardComponent.new(title: "Your drafts", id: "d", empty: "No drafts.") do |card|
      card.with_row { "A row" }
      card.with_empty_action { '<a href="#x">Start a draft</a>'.html_safe }
    end
    assert_no_selector "p[data-card-empty]"
    assert_no_text "Start a draft"
  end

  # Spec, Ruling 5: the hint under a short list is gone, also with rows.
  test "there is no hint line any more" do
    assert_raises(ArgumentError) { Admin::DashboardScreen::CardComponent.new(title: "Going live next", id: "g", empty: "None", hint: "Schedule a draft to see it here.") }
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

  # The notes inbox's way on, in words under the rows (notes handoff, "Inbox
  # row": the footer), for a card that passes no `link:`.
  test "a footer stands under the rows, and a card without one has none" do
    render_inline Admin::DashboardScreen::CardComponent.new(title: "Notes for you", id: "n", empty: "None") do |card|
      card.with_row { "A row" }
      card.with_footer { "All notes for you →" }
    end

    assert_selector "section > ul + footer", text: "All notes for you →"
    assert_no_selector "header a"

    render_inline Admin::DashboardScreen::CardComponent.new(title: "Drafts", id: "d", empty: "None") { |card| card.with_row { "A row" } }
    assert_no_selector "footer"
  end
end
