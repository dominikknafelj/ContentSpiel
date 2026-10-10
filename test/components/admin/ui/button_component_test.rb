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
    render_inline Admin::Ui::ButtonComponent.new(label: "Add row", type: "submit", data: { action: "click->admin--groups#add" })

    assert_selector "button[type='submit'][data-action='click->admin--groups#add']", text: "Add row"
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
    assert_selector "button.border-line-strong.text-danger-ink", text: "Move to trash"
    assert_no_selector "button.bg-danger-tint"
    assert_raises(ArgumentError) { Admin::Ui::ButtonComponent.new(label: "x", variant: :danger_outline) }
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
