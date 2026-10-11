require "test_helper"

# The bubble shown while its host is hovered or holds the keyboard's focus
# (presence handoff 18): never a `title`, which a keyboard does not reach.
# What moves is `admin--ui--tooltip`'s, tested on its first hosts, presence's
# circles (`test/system/admin/presence_test.rb`, "a circle's tooltip…").
class Admin::Ui::TooltipComponentTest < ViewComponent::TestCase
  test "a hidden bubble with the inverted toast's look, 6px under its host and centred" do
    render_inline(Admin::Ui::TooltipComponent.new(text: "Dana Weiss · here"))

    bubble = page.find("span[data-tooltip][hidden][data-admin--ui--tooltip-target=bubble]", visible: :all)
    assert_equal "Dana Weiss · here", bubble.text(:all)
    classes = bubble[:class].split
    %w[bg-ink text-paper rounded-cs font-cs text-xs leading-[1.4] px-2 py-1 max-w-60 absolute top-full mt-1.5 left-1/2 -translate-x-1/2 pointer-events-none].each { |name| assert_includes classes, name }
    assert_empty classes.grep(/shadow|border/)
    # When centred would cross an edge the script says which, and it lines up
    # with the host's edge there.
    %w[data-[align=left]:left-0 data-[align=left]:translate-x-0 data-[align=right]:right-0 data-[align=right]:left-auto data-[align=right]:translate-x-0].each { |name| assert_includes classes, name }
    # The host's own `aria-label` says it: the bubble is not read twice.
    assert_equal "true", bubble["aria-hidden"]
    assert_no_selector "[title]", visible: :all
  end

  test "what its host carries: the place it is put against, the controller and the five things it hears" do
    assert_equal "relative", Admin::Ui::TooltipComponent::HOST
    data = Admin::Ui::TooltipComponent.host_data
    assert_equal "admin--ui--tooltip", data[:controller]
    assert_equal %w[mouseenter->admin--ui--tooltip#enter mouseleave->admin--ui--tooltip#leave focusin->admin--ui--tooltip#focus
                    focusout->admin--ui--tooltip#leave pointerdown->admin--ui--tooltip#dismiss], data[:action].split
  end
end
