require "test_helper"

# `Admin::Ui::RecordChipComponent`: a kind of record as its module's chip,
# alone or with its word.
class Admin::Ui::RecordChipComponentTest < ViewComponent::TestCase
  FAMILIES = Admin::Ui::IconChipComponent::FAMILIES

  def chip_classes = page.find("span.rounded-chip[aria-hidden='true']", visible: :all)["class"].split

  test "a kind is its module's chip: pages structure, posts lists, media media, forms form, settings code" do
    { "page" => :structure, "post" => :lists, "media" => :media, "form" => :form, "settings" => :code }.each do |kind, family|
      render_inline Admin::Ui::RecordChipComponent.new(kind: kind)

      FAMILIES.fetch(family).split.each { |utility| assert_includes chip_classes, utility, kind }
      assert_includes chip_classes, Admin::Ui::IconChipComponent::SIZES.fetch(:xsmall), kind
      assert_selector "span[aria-hidden='true'] svg", visible: :all
      assert_equal "", page.text.squish, "#{kind}'s chip alone has no words"
    end
  end

  test "with a label it is the chip and the word, the chip hidden from a screen reader" do
    render_inline Admin::Ui::RecordChipComponent.new(kind: "post", label: "Post")

    assert_equal "Post", page.text.squish
    assert_selector "span.inline-flex.items-center.gap-1\\.5 > span.rounded-chip[aria-hidden='true'] + span.text-small.text-dim", exact_text: "Post"
    assert_no_selector "[tabindex], [role], button, a"
  end

  # Every kind a list can show is held here from the lists' own constants,
  # so a kind added to one of them fails until it has a chip.
  test "every kind Trash and Translations can list has a chip, and an unknown kind is refused" do
    kinds = Admin::TrashScreen::RowComponent::TYPE_KEYS.values + Admin::TranslationsController::TYPES.keys
    kinds.uniq.each do |kind|
      render_inline Admin::Ui::RecordChipComponent.new(kind: kind, label: kind)

      assert_selector "span.rounded-chip[aria-hidden='true'] svg", visible: :all
    end
    assert_raises(ArgumentError) { Admin::Ui::RecordChipComponent.new(kind: "tag") }
  end
end
