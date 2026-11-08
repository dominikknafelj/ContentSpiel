require "test_helper"

# A system's state (mail, the AI key, a system check): a dot and a word on
# its role's tint, or outlined when off. The word says the state; the dot
# is a second cue a screen reader never hears.
class Admin::Ui::StateChipComponentTest < ViewComponent::TestCase
  def chip_classes = page.find("span.admin-state-chip")["class"].split

  def dot_classes = page.find("span.admin-state-chip > span[aria-hidden=true]", visible: :all)["class"].split

  test "each tone draws its ground, its 6px dot and its word, the dot hidden from a screen reader" do
    %i[ok warn danger].each do |tone|
      render_inline Admin::Ui::StateChipComponent.new(tone: tone, label: "Working")

      assert_selector "span.admin-state-chip[data-state-tone=#{tone}]", text: "Working"
      assert_includes chip_classes, "bg-#{tone}-tint", tone
      assert_includes chip_classes, "text-#{tone}-ink", tone
      %w[rounded-cs px-2 py-0.5 text-label].each { |utility| assert_includes chip_classes, utility, tone }
      assert_includes dot_classes, "bg-#{tone}", tone
      assert_includes dot_classes, "size-1.5", tone
      assert_includes dot_classes, "rounded-full", tone
    end
  end

  test "off is an outline with a hollow ring and dim words" do
    render_inline Admin::Ui::StateChipComponent.new(tone: :off, label: "Off")

    assert_selector "span.admin-state-chip[data-state-tone=off]", text: "Off"
    assert_includes chip_classes, "border-field-line"
    assert_includes chip_classes, "text-dim"
    assert_empty chip_classes.grep(/\Abg-/)
    assert_includes dot_classes, "border"
    assert_includes dot_classes, "border-field-line"
    assert_empty dot_classes.grep(/\Abg-/)
  end

  test "a detail is small meta text after the chip, and the two read as one phrase" do
    render_inline Admin::Ui::StateChipComponent.new(tone: :ok, label: "Key saved", detail: "added 2 Oct", data: { ai_key_state: "set" })

    assert_equal "Key saved", page.find("span.admin-state-chip").text.squish
    assert_selector "span[data-ai-key-state=set] > span.admin-state-chip + span.text-small.text-meta", text: "· added 2 Oct"
    assert_equal "Key saved · added 2 Oct", page.find("span[data-ai-key-state=set]").text.squish

    render_inline Admin::Ui::StateChipComponent.new(tone: :ok, label: "Key saved")
    assert_equal "Key saved", page.find("span.admin-state-chip").text.squish
    assert_no_selector ".text-meta"
  end

  test "an unknown tone is refused" do
    assert_raises(ArgumentError) { Admin::Ui::StateChipComponent.new(tone: :live, label: "Live") }
    assert_equal %i[ok warn danger off], Admin::Ui::StateChipComponent::TONES
  end

  test "it takes no focus and has no role" do
    render_inline Admin::Ui::StateChipComponent.new(tone: :warn, label: "No key", detail: "x")

    assert_no_selector "[tabindex], [role], button, a"
  end

  test "the caller's attributes pass through" do
    render_inline Admin::Ui::StateChipComponent.new(tone: :ok, label: "Key saved", data: { ai_key_state: "set" })

    assert_selector "span.admin-state-chip[data-ai-key-state=set][data-state-tone=ok]"
  end
end
