require "test_helper"

# Tabs that are links (the Trash screen's, a form's Form | Submissions): the
# current one inverted and `aria-current`, a count only where one is given.
class Admin::Ui::TabLinksComponentTest < ViewComponent::TestCase
  test "the current tab is marked, and a count is drawn only when given" do
    render_inline Admin::Ui::TabLinksComponent.new(label: "Screens", link_data: { turbo_frame: "content" }, tabs: [
      { label: "Form", href: "/f", current: false }, { label: "Submissions", href: "/s", current: true, count: 3 }
    ])

    assert_equal [ "Form", "Submissions 3" ], page.all("nav[aria-label='Screens'] a").map { |a| a.text.squish }
    assert_selector "a[aria-current=page][href='/s'].bg-ink", text: "Submissions"
    assert_selector "nav[aria-label='Screens'].rounded-cs.overflow-hidden"
    assert_selector "a[href='/f'][data-turbo-frame=content]:not([aria-current])"
    assert_no_selector "a[href='/f'] span", wait: 0
  end

  test "the current tab is the ink segment with paper words at 600 and no inset ring; the others dim" do
    render_inline Admin::Ui::TabLinksComponent.new(label: "Screens", tabs: [
      { label: "All", href: "/a", current: false, count: 4 }, { label: "Unread", href: "/u", current: true, count: 2 }
    ])

    assert_selector "a[aria-current=page].bg-ink.text-paper.font-semibold.focus-visible\\:inset-ring-4.focus-visible\\:inset-ring-paper"
    assert_no_selector "a[aria-current=page].ring-2", wait: 0
    assert_no_selector "a[aria-current=page].hover\\:bg-sunken", wait: 0
    assert_selector "a[href='/a'].text-dim.hover\\:bg-sunken:not(.bg-ink)"
    assert_selector "a[href='/a'].focus-visible\\:outline-2.focus-visible\\:-outline-offset-2.focus-visible\\:outline-accent"
    assert_selector "a[href='/u'] span.text-count", text: "2"
  end

  test "the frame is the field line on the surface, the cs radius, with a line rule between the segments" do
    render_inline Admin::Ui::TabLinksComponent.new(label: "Screens", tabs: [
      { label: "A", href: "/a", current: true }, { label: "B", href: "/b", current: false }
    ])

    assert_selector "nav.rounded-cs.border.border-field-line.bg-surface"
    assert_selector "a.border-r.border-line.last\\:border-r-0.px-3.py-1\\.5.text-sm", count: 2
  end

  test "no tabs draw nothing" do
    render_inline Admin::Ui::TabLinksComponent.new(label: "Screens", tabs: [])
    assert_no_selector "nav", wait: 0
  end
end
