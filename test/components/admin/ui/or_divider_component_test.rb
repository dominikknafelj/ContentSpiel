require "test_helper"

class Admin::Ui::OrDividerComponentTest < ViewComponent::TestCase
  test "the word between two rules, hidden from a screen reader as a whole" do
    render_inline Admin::Ui::OrDividerComponent.new
    divider = page.find("div[aria-hidden=true]", text: "or", visible: :all)
    assert_equal "or", divider.text.squish
    assert_equal 2, divider.all("span.h-px", visible: :all).size
    assert_nil divider[:hidden]
  end

  test "it is drawn hidden when asked, and passes its own attributes through" do
    render_inline Admin::Ui::OrDividerComponent.new(hidden: true, data: { passkey_sign_in_target: "divider" })
    assert_selector "div[hidden][aria-hidden=true][data-passkey-sign-in-target=divider]", visible: :all
  end
end
