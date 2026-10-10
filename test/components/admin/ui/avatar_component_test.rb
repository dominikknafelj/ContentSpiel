require "test_helper"

# The one drawing of a person's circle (notes' avatar and presence's people
# both draw through it).
class Admin::Ui::AvatarComponentTest < ViewComponent::TestCase
  test "initials in a round mono circle, upper-case by style and hidden from a screen reader" do
    render_inline(Admin::Ui::AvatarComponent.new(initials: "dw", size: :md))

    assert_selector "span.flex.shrink-0.items-center.justify-center.rounded-full.font-cs-mono.font-medium.uppercase.leading-none.size-6.text-\\[9px\\]" \
                    ".border.border-line-strong.bg-sunken.text-ink[aria-hidden=true]", text: "dw", exact_text: true
    assert_no_selector ".ring-2"
  end

  test "the small size, the viewer's own filled tone and the unfilled away tone" do
    render_inline(Admin::Ui::AvatarComponent.new(initials: "DW", size: :sm, tone: :own))
    assert_selector "span.size-5.text-\\[8px\\].bg-ink.text-paper"
    assert_no_selector ".border"

    render_inline(Admin::Ui::AvatarComponent.new(initials: "DW", size: :md, tone: :away))
    assert_selector "span.border.border-line.bg-paper.text-meta"
    assert_no_selector ".bg-sunken, .border-line-strong, .text-ink"
  end

  test "a ring in the colour of what the circles stand on, for circles that overlap" do
    render_inline(Admin::Ui::AvatarComponent.new(initials: "DW", size: :md, ring: :paper))
    assert_selector "span.ring-2.ring-paper"

    render_inline(Admin::Ui::AvatarComponent.new(initials: "DW", size: :sm, ring: :surface))
    assert_selector "span.ring-2.ring-surface"
    assert_no_selector ".ring-paper"
    assert_raises(KeyError) { Admin::Ui::AvatarComponent.new(initials: "DW", size: :md, ring: :pink) }
  end

  test "an unknown size or tone is refused" do
    assert_raises(KeyError) { Admin::Ui::AvatarComponent.new(initials: "DW", size: :huge) }
    assert_raises(KeyError) { Admin::Ui::AvatarComponent.new(initials: "DW", size: :md, tone: :green) }
  end
end
