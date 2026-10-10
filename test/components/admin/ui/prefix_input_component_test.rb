require "test_helper"

class Admin::Ui::PrefixInputComponentTest < ViewComponent::TestCase
  test "a sunken prefix cell joined to the input, one border around both" do
    render_inline(Admin::Ui::PrefixInputComponent.new(name: "slug", id: "slug", value: "about", prefix: "example.com/"))
    assert_selector ".admin-prefix-input span.bg-sunken", text: "example.com/"
    assert_selector ".admin-prefix-input input#slug[name=slug][value=about]"
  end

  test "with errors the wrapper turns danger and the input is described by them" do
    render_inline(Admin::Ui::PrefixInputComponent.new(name: "slug", id: "slug", value: "", prefix: "/", errors: [ "can't be blank" ]))
    assert_selector ".admin-prefix-input.border-danger input[aria-invalid=true][aria-describedby='slug-errors']"
    assert_selector ".admin-prefix-input span.bg-sunken"
  end
end
