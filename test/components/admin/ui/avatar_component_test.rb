require "test_helper"

# The one drawing of a person's circle (notes' avatar, presence's people and
# the scripts' circles are all this one).
class Admin::Ui::AvatarComponentTest < ViewComponent::TestCase
  test "every size draws its initials at 11px, weight 600, upper-case" do
    { lg: "size-7", md: "size-\\[26px\\]", sm: "size-\\[22px\\]" }.each do |size, diameter|
      render_inline(Admin::Ui::AvatarComponent.new(initials: "dw", size: size))

      assert_selector "span.flex.shrink-0.items-center.justify-center.rounded-full.text-count.font-semibold.uppercase.leading-none.#{diameter}[aria-hidden=true]",
        text: "dw", exact_text: true
    end
    assert_no_selector ".ring-2, .inset-ring-\\[1\\.5px\\]"
    assert_equal "11px", Rails.root.join("app/assets/tailwind/content-spiel.css").read[/--cs-t-count:\s*([^;]+);/, 1]
  end

  test "other is the people tint with people letters, own the solid people fill with surface letters, away a dashed edge on surface" do
    render_inline(Admin::Ui::AvatarComponent.new(initials: "DW", size: :md))
    assert_selector "span.bg-people-tint.text-people"
    assert_no_selector ".border-dashed, .bg-people, .text-ink"

    render_inline(Admin::Ui::AvatarComponent.new(initials: "DW", size: :md, tone: :own))
    assert_selector "span.bg-people.text-surface"
    assert_no_selector ".bg-people-tint, .border-dashed"

    render_inline(Admin::Ui::AvatarComponent.new(initials: "DW", size: :md, tone: :away))
    assert_selector "span.border-\\[1\\.5px\\].border-dashed.border-field-line.bg-surface.text-meta"
    assert_no_selector ".bg-people-tint, .bg-people, .text-people"

    render_inline(Admin::Ui::AvatarComponent.new(initials: "+3", size: :md, tone: :more))
    assert_selector "span.border.border-meta.bg-surface.text-ink[aria-hidden=true]", text: "+3"
    assert_no_selector ".bg-sunken"

    render_inline(Admin::Ui::AvatarComponent.new(initials: "", size: :md, tone: :empty))
    assert_selector "span.border.border-field-line.bg-surface"
    assert_no_selector ".border-dashed, .bg-people-tint, .text-people"
  end

  test "here adds the inner people ring, and there is no outer ring" do
    render_inline(Admin::Ui::AvatarComponent.new(initials: "DW", size: :sm, here: true))
    assert_selector "span.inset-ring-\\[1\\.5px\\].inset-ring-people"
    assert_no_selector "[class*='ring-2'], [class*='ring-paper'], [class*='ring-surface'], [class*='avatar-ground']"
  end

  test "+N past nine reads 9+" do
    assert_equal "+1", Admin::Ui::AvatarComponent.more_label(1)
    assert_equal "+9", Admin::Ui::AvatarComponent.more_label(9)
    assert_equal "9+", Admin::Ui::AvatarComponent.more_label(10)
    assert_equal "9+", Admin::Ui::AvatarComponent.more_label(40)
    assert_equal [ "1", "9", "9+" ], [ 1, 9, 10 ].map { |count| Admin::Ui::AvatarComponent.count_label(count) }, "a count circle says everyone, with the same limit"
  end

  test "the scripts' circle is the component's: ui/avatar.js holds its size and tone classes" do
    script = Rails.root.join("app/javascript/ui/avatar.js").read
    classes = [ Admin::Ui::AvatarComponent::LETTERS, *Admin::Ui::AvatarComponent::SIZES.values, *Admin::Ui::AvatarComponent::TONES.values ]
    assert_includes script, "unknown avatar size", "an unknown size is refused as the component refuses it"
    assert_includes script, "unknown avatar tone"
    classes.each { |group| assert_includes script, %("#{group}"), "ui/avatar.js lacks #{group.inspect}" }
  end

  test "an unknown size or tone is refused" do
    assert_raises(KeyError) { Admin::Ui::AvatarComponent.new(initials: "DW", size: :huge) }
    assert_raises(KeyError) { Admin::Ui::AvatarComponent.new(initials: "DW", size: :md, tone: :green) }
    assert_raises(ArgumentError) { Admin::Ui::AvatarComponent.new(initials: "DW", size: :sm, ring: :paper) }
  end
end
