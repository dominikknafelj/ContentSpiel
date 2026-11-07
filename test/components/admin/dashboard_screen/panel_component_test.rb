require "test_helper"

class Admin::DashboardScreen::PanelComponentTest < ViewComponent::TestCase
  def panel(kind: :action, title: "Pick up where you left off", line: "Your drafts, the latest first.", id: "d", empty: "None", **options, &block)
    render_inline(Admin::DashboardScreen::PanelComponent.new(kind:, title:, line:, id:, empty:, **options), &block)
  end

  test "each kind marks its head: action, shortcuts, information" do
    assert_equal %i[action shortcuts information], Admin::DashboardScreen::PanelComponent::KINDS
    Admin::DashboardScreen::PanelComponent::KINDS.each do |kind|
      panel(kind:)
      assert_selector "section.admin-dashboard-panel.admin-dashboard-panel--#{kind} > header.admin-dashboard-panel__head"
      assert_selector "[class*='admin-dashboard-panel--']", count: 1
    end

    assert_raises(ArgumentError) { Admin::DashboardScreen::PanelComponent.new(kind: :other, title: "x", line: "y", id: "o", empty: "None") }
  end

  test "the heading and its one line stand in the head, and the section is named by the heading" do
    panel(kind: :shortcuts, title: "Pick up where you left off", line: "Your drafts, the latest first.")

    assert_selector "section[aria-labelledby=d] > header.admin-dashboard-panel__head h2#d.text-h3", exact_text: "Pick up where you left off"
    assert_selector "header.admin-dashboard-panel__head p.admin-dashboard-panel__line.text-sm", exact_text: "Your drafts, the latest first."
    assert_selector "h2", count: 1
    assert_selector "p.admin-dashboard-panel__line", count: 1
  end

  test "caps its rows at five and links on with the arrow" do
    panel(link: [ "/cs-studio/posts?status=draft", "All drafts" ]) do |card|
      8.times { |i| card.with_row { "Row #{i}" } }
    end

    assert_selector "li", count: 5
    assert_no_text "Row 5"
    assert_selector "header a[href='/cs-studio/posts?status=draft'][aria-label='All drafts']", text: "→"
  end

  test "an explicit limit raises the cap" do
    panel(kind: :information, title: "What changed recently", limit: 15) do |card|
      8.times { |i| card.with_row { "Row #{i}" } }
    end

    assert_selector "li", count: 8
  end

  # An empty panel says one line in dim, left-aligned where its first row
  # would be, with its action (if any) after it. No centred bold title, no
  # 48px of padding.
  test "an empty panel says one line where its first row would be, in dim, with its action after it" do
    panel(empty: "No drafts.") do |card|
      card.with_empty_action { '<a href="#x">Start a draft</a>'.html_safe }
    end

    assert_selector "section > header + p[data-panel-empty].px-4.text-sm.text-dim", text: /\ANo drafts\.\s+Start a draft\z/
    assert_selector "p[data-panel-empty] a[href='#x']", text: "Start a draft"
    assert_no_selector ".admin-empty-state, h3, ul"
  end

  test "an empty panel without an action says its line alone, and a panel with rows draws neither" do
    panel(kind: :information, title: "Publishing on its own", empty: "Nothing scheduled.")
    assert_selector "p[data-panel-empty]", exact_text: "Nothing scheduled."
    assert_no_selector "a"

    panel(empty: "No drafts.") do |card|
      card.with_row { "A row" }
      card.with_empty_action { '<a href="#x">Start a draft</a>'.html_safe }
    end
    assert_no_selector "p[data-panel-empty]"
    assert_no_text "Start a draft"
  end

  test "there is no hint line" do
    assert_raises(ArgumentError) { Admin::DashboardScreen::PanelComponent.new(kind: :action, title: "x", line: "y", id: "g", empty: "None", hint: "Schedule a draft.") }
  end

  # The notes panels' head extras: a count beside the heading and an action
  # before the arrow.
  test "a badge stands beside the heading and an action before the arrow" do
    panel(title: "Notes for you", line: "Mentions and replies addressed to you.", link: [ "/cs-studio/notes", "All notes for you" ]) do |card|
      card.with_badge { "<span>3 new</span>".html_safe }
      card.with_action { "Mark all read" }
    end

    assert_selector "header h2 + span", exact_text: "3 new"
    assert_selector "header", text: /\A\s*Notes for you\s*3 new\s*Mentions and replies addressed to you\.\s*Mark all read\s*→\s*\z/
  end

  # A panel whose way to the fuller list is said in words under the rows,
  # for a panel that passes no `link:`.
  test "a footer stands under the rows, and a panel without one has none" do
    panel(title: "Notes for you") do |card|
      card.with_row { "A row" }
      card.with_footer { "All notes for you →" }
    end

    assert_selector "section > ul + footer", text: "All notes for you →"
    assert_no_selector "header a"

    panel { |card| card.with_row { "A row" } }
    assert_no_selector "footer"
  end

  # Pick up where you left off lays its rows out as tiles: no rules between
  # them, each tile its own card, capped like rows.
  test "layout: :tiles draws the rows as a list of tiles, capped at five" do
    panel(kind: :shortcuts, layout: :tiles) do |card|
      8.times { |i| card.with_row { "Tile #{i}" } }
    end

    assert_selector "section > ul.admin-draft-tiles > li", count: 5
    assert_no_selector "li.border-b"
    assert_no_text "Tile 5"

    panel(kind: :shortcuts, layout: :tiles)
    assert_selector "p[data-panel-empty]", text: "None"
    assert_no_selector "ul"

    assert_raises(ArgumentError) { Admin::DashboardScreen::PanelComponent.new(kind: :action, title: "x", line: "y", id: "o", empty: "None", layout: :grid) }
  end
end
