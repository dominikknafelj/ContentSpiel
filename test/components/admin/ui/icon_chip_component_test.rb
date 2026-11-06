require "test_helper"

# Icon chips: a block type's or a module's icon on a tinted
# square in the hue of its family. Decoration: the name is always beside it.
class Admin::Ui::IconChipComponentTest < ViewComponent::TestCase
  FAMILIES = ContentModel::BlockTypeDefinition::ICON_FAMILIES

  test "each family draws its icon on its chip, 24px with a 7px radius" do
    FAMILIES.each do |family|
      render_inline Admin::Ui::IconChipComponent.new(icon: :pilcrow, family: family)
      assert_selector "span[class~='size-6'][class~='rounded-chip'][class~='bg-ic-#{family}-bg'][class~='text-ic-#{family}'] svg[class~='size-3.5']", count: 1
    end
  end

  test "the small chip is 22px, the icon still 14px" do
    render_inline Admin::Ui::IconChipComponent.new(icon: :columns_2, family: :structure, size: :small)
    assert_selector "span[class~='size-5.5'][class~='rounded-chip'] svg[class~='size-3.5']"
  end

  test "people is a hue of its own" do
    render_inline Admin::Ui::IconChipComponent.new(icon: :pilcrow, family: :people)
    assert_selector "span[class~='bg-ic-people-bg'][class~='text-ic-people']"
  end

  test "accent and neutral are the tint pair and the sunken pair" do
    render_inline Admin::Ui::IconChipComponent.new(icon: :pilcrow, family: :accent)
    assert_selector "span[class~='bg-accent-tint'][class~='text-accent']"
    render_inline Admin::Ui::IconChipComponent.new(icon: :pilcrow, family: :neutral)
    assert_selector "span[class~='bg-sunken'][class~='text-dim']"
  end

  test "an unknown family or size raises" do
    assert_raises(ArgumentError) { Admin::Ui::IconChipComponent.new(icon: :pilcrow, family: :purple) }
    assert_raises(ArgumentError) { Admin::Ui::IconChipComponent.new(icon: :pilcrow, family: nil) }
    assert_raises(ArgumentError) { Admin::Ui::IconChipComponent.new(icon: :pilcrow, family: :text, size: :xl) }
  end

  test "the chip is hidden from a screen reader and has no words of its own" do
    render_inline Admin::Ui::IconChipComponent.new(icon: :pilcrow, family: :text)
    assert_selector "span[aria-hidden=true]"
    assert_equal "", page.text.strip
  end

  test "extra html passes through and the class joins the chip's" do
    render_inline Admin::Ui::IconChipComponent.new(icon: :pilcrow, family: :text, id: "x", data: { block_icon: "pilcrow" })
    assert_selector "span#x[data-block-icon=pilcrow][class~='rounded-chip']"
  end
end
