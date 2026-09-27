require "test_helper"

class Admin::ButtonComponentTest < ViewComponent::TestCase
  test "renders a button with the given label and defaults to type button, variant primary" do
    render_inline Admin::ButtonComponent.new(label: "Save")

    assert_selector "button[type='button']", text: "Save"
  end

  test "secondary and danger variants render distinct classes" do
    render_inline Admin::ButtonComponent.new(label: "Cancel", variant: :secondary)
    secondary_class = page.find("button")["class"]

    render_inline Admin::ButtonComponent.new(label: "Delete", variant: :danger)
    danger_class = page.find("button")["class"]

    refute_equal secondary_class, danger_class
  end

  test "passes through arbitrary html attributes, e.g. type submit and data attributes" do
    render_inline Admin::ButtonComponent.new(label: "Add row", type: "submit", data: { action: "click->admin--groups#add" })

    assert_selector "button[type='submit'][data-action='click->admin--groups#add']", text: "Add row"
  end

  test "rejects an unknown variant" do
    assert_raises(ArgumentError) { Admin::ButtonComponent.new(label: "Save", variant: :nope) }
  end
end
