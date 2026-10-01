require "test_helper"

class Admin::FlashComponentTest < ViewComponent::TestCase
  test "renders a notice as a status and an alert as an alert" do
    render_inline Admin::FlashComponent.new(notice: "Saved", alert: "Something went wrong")

    assert_selector "p[role=status]", text: "Saved"
    assert_selector "p[role=alert]", text: "Something went wrong"
  end

  test "renders nothing without a message" do
    render_inline Admin::FlashComponent.new(notice: nil, alert: "")

    assert_no_selector "[role=status]"
    assert_no_selector "[role=alert]"
    assert_equal "", rendered_content.strip
  end

  test "an action renders as a button_to posting to its url" do
    render_inline Admin::FlashComponent.new(notice: "Moved “About” to the trash", alert: nil,
      action: { label: "Undo", url: "/cs-studio/trash/page/1/restore", method: :post })

    assert_selector "form[action='/cs-studio/trash/page/1/restore'][method=post] button", text: "Undo"
    assert_no_selector "input[name=_method]"
  end

  test "an action's method other than post goes through Rails' _method" do
    render_inline Admin::FlashComponent.new(notice: "Done", alert: nil, action: { label: "Revert", url: "/x", method: :delete })

    assert_selector "form[action='/x'] input[name=_method][value=delete]", visible: :all
  end

  test "messages are escaped" do
    render_inline Admin::FlashComponent.new(notice: "<b>bold</b>", alert: nil)

    assert_no_selector "b"
    assert_text "<b>bold</b>"
  end
end
