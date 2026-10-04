require "test_helper"

class Admin::SelectComponentTest < ViewComponent::TestCase
  test "renders a styled select with the selected option" do
    render_inline(Admin::SelectComponent.new(name: "status", id: "status", options: [ %w[Draft draft], %w[Published published] ],
      selected: "published", include_blank: "Any", class: "w-full"))
    assert_selector "select.cs-select.w-full[name=status]#status"
    assert_selector "option[selected][value=published]", text: "Published"
    assert_selector "option[value='']", text: "Any"
  end
end
