require "test_helper"

# The bubble shown while its host is hovered or holds the focus: never a
# `title`, which a keyboard does not reach.
class Admin::Ui::TooltipComponentTest < ViewComponent::TestCase
  test "a hidden bubble under its host that hover and focus of the host show" do
    render_inline(Admin::Ui::TooltipComponent.new(text: "Dana Weiss · here"))

    bubble = page.find("span[data-tooltip]", visible: :all)
    assert_equal "Dana Weiss · here", bubble.text(:all)
    classes = bubble[:class].split
    %w[hidden absolute top-full pointer-events-none group-hover/tip:block group-focus/tip:block right-0].each { |name| assert_includes classes, name }
    # The host's own `aria-label` says it: the bubble is not read twice.
    assert_equal "true", bubble["aria-hidden"]
    assert_no_selector "[title]", visible: :all
  end

  test "it hangs from the left edge when asked, and the host's classes are the group it answers to" do
    render_inline(Admin::Ui::TooltipComponent.new(text: "x", align: :left))

    assert_selector "span[data-tooltip].left-0", visible: :all
    assert_no_selector ".right-0", visible: :all
    assert_equal "group/tip relative", Admin::Ui::TooltipComponent::HOST
    assert_raises(ArgumentError) { Admin::Ui::TooltipComponent.new(text: "x", align: :middle) }
  end
end
