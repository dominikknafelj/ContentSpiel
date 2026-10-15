require "test_helper"

class Admin::Ui::ButtonComponentTest < ViewComponent::TestCase
  test "renders a button with the given label and defaults to type button, variant primary" do
    render_inline Admin::Ui::ButtonComponent.new(label: "Save")

    assert_selector "button[type='button']", text: "Save"
  end

  test "secondary and danger variants render distinct classes" do
    render_inline Admin::Ui::ButtonComponent.new(label: "Cancel", variant: :secondary)
    secondary_class = page.find("button")["class"]

    render_inline Admin::Ui::ButtonComponent.new(label: "Delete", variant: :danger)
    danger_class = page.find("button")["class"]

    refute_equal secondary_class, danger_class
  end

  test "passes through arbitrary html attributes, e.g. type submit and data attributes" do
    render_inline Admin::Ui::ButtonComponent.new(label: "Add row", type: "submit", data: { action: "click->admin--editor--groups#add" })

    assert_selector "button[type='submit'][data-action='click->admin--editor--groups#add']", text: "Add row"
  end

  test "rejects an unknown variant" do
    assert_raises(ArgumentError) { Admin::Ui::ButtonComponent.new(label: "Save", variant: :nope) }
  end

  test "the ghost variant is accepted" do
    render_inline Admin::Ui::ButtonComponent.new(label: "Cancel", variant: :ghost)

    assert_selector "button.text-dim", text: "Cancel"
  end

  test "danger_text is a secondary button with danger-coloured text; danger_outline is gone" do
    render_inline(Admin::Ui::ButtonComponent.new(label: "Move to trash", variant: :danger_text))
    assert_selector "button.border-field-line.text-danger-ink", text: "Move to trash"
    assert_no_selector "button.bg-danger-tint"
    assert_raises(ArgumentError) { Admin::Ui::ButtonComponent.new(label: "x", variant: :danger_outline) }
  end

  test "a secondary button is outlined in the field line and answers the pointer with an ink border, only while enabled" do
    render_inline Admin::Ui::ButtonComponent.new(label: "Preview", variant: :secondary)
    classes = page.find("button")["class"].split

    assert_includes classes, "border-field-line"
    assert_includes classes, "not-disabled:hover:border-ink"
    assert_not_includes classes, "hover:bg-sunken"
  end

  test "no variant answers the pointer while disabled: every hover is not-disabled:hover:" do
    Admin::Ui::ButtonComponent::VARIANT_CLASSES.each do |variant, classes|
      assert_empty classes.split.grep(/\Ahover:/), variant
    end
  end

  # Contrast and buttons spec (D1, Ruling 11): one disabled look for every
  # variant, sunken with meta words and a hairline, no accent and no opacity;
  # a busy button (`aria-busy`) keeps its variant's look.
  test "every variant is drawn disabled the same way, and a busy one is not" do
    Admin::Ui::ButtonComponent::VARIANT_CLASSES.each_key do |variant|
      render_inline Admin::Ui::ButtonComponent.new(label: "Save", variant: variant, disabled: true)
      classes = page.find("button[disabled]")["class"].split

      %w[disabled:not-aria-busy:border-line disabled:not-aria-busy:bg-sunken disabled:not-aria-busy:text-meta aria-busy:cursor-progress].each do |name|
        assert_includes classes, name, variant
      end
      assert_empty classes.grep(/opacity-50/), variant
    end
  end

  # A disabled button must not change size: the save bar's Save is toggled by
  # script, so every variant has its 1px border at rest and the disabled look
  # only recolours it.
  test "every variant has a border at rest, so disabling one changes no size" do
    Admin::Ui::ButtonComponent::VARIANT_CLASSES.each do |variant, classes|
      assert_includes classes.split, "border", variant
      assert_not_includes Admin::Ui::ButtonComponent::COMMON_CLASS.split, "disabled:not-aria-busy:border"
    end
  end

  test "solid danger stays the dialog confirm" do
    render_inline Admin::Ui::ButtonComponent.new(label: "Delete", variant: :danger)
    assert_selector "button.bg-danger", text: "Delete"
  end

  test "small swaps the padding for a compact one and keeps the variant" do
    render_inline Admin::Ui::ButtonComponent.new(label: "Use", size: :small)
    assert_selector "button.bg-accent.px-2.py-0\\.5.text-sm", text: "Use"
    assert_no_selector "button.px-4"
    assert_raises(ArgumentError) { Admin::Ui::ButtonComponent.new(label: "x", size: :huge) }
  end
end
