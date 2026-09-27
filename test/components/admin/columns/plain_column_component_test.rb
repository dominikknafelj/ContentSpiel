require "test_helper"

class Admin::Columns::PlainColumnComponentTest < ViewComponent::TestCase
  test "renders a text input by default" do
    render_inline Admin::Columns::PlainColumnComponent.new(name: "caption", value: "A caption")

    assert_selector "input[type=text][name=caption][value='A caption']"
  end

  test "renders a textarea when multiline" do
    render_inline Admin::Columns::PlainColumnComponent.new(name: "meta_description", value: "A description", multiline: true)

    assert_selector "textarea[name=meta_description]", text: "A description"
  end

  test "shows the read-only original and errors" do
    render_inline Admin::Columns::PlainColumnComponent.new(name: "caption", value: nil, original: "Bildunterschrift", errors: [ "is too long" ])

    assert_selector "[data-original-for='caption']", text: "Bildunterschrift"
    assert_text "is too long"
  end
end
