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
    assert_selector "nav[aria-label='Screens'].rounded-button.overflow-hidden"
    assert_selector "a[aria-current=page].text-paper.ring-2.ring-inset.ring-paper"
    assert_selector "a[href='/f'][data-turbo-frame=content]:not([aria-current])"
    assert_no_selector "a[href='/f'] span", wait: 0
  end

  test "no tabs draw nothing" do
    render_inline Admin::Ui::TabLinksComponent.new(label: "Screens", tabs: [])
    assert_no_selector "nav", wait: 0
  end
end
