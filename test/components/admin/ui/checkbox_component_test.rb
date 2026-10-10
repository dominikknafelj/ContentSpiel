require "test_helper"

class Admin::Ui::CheckboxComponentTest < ViewComponent::TestCase
  test "a token-styled native checkbox with its label" do
    render_inline(Admin::Ui::CheckboxComponent.new(name: "user[group_ids][]", value: "3", checked: true, id: "group-3", label: "Editors"))
    assert_selector "input#group-3.cs-checkbox[type=checkbox][name='user[group_ids][]'][value='3'][checked]"
    assert_selector "label[for='group-3']", text: "Editors"
  end

  test "disabled is passed through" do
    render_inline(Admin::Ui::CheckboxComponent.new(name: "x", disabled: true))
    assert_selector "input.cs-checkbox[disabled]"
  end

  test "extra html attributes reach the input and no label renders without one" do
    render_inline(Admin::Ui::CheckboxComponent.new(name: "x", id: "x-1", data: { action: "change->a#b" }, aria: { label: "Pick" }))
    assert_selector "input#x-1[data-action='change->a#b'][aria-label=Pick]"
    assert_no_selector "label"
  end
end
