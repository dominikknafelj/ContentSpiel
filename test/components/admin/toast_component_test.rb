require "test_helper"

class Admin::ToastComponentTest < ViewComponent::TestCase
  test "success is a status that hides after four seconds" do
    render_inline(Admin::ToastComponent.new(message: "Saved."))
    assert_selector ".admin-toast[role=status][data-controller='admin--toast'][data-admin--toast-timeout-value='4000']", text: "Saved."
  end

  test "undo carries its action and stays eight seconds" do
    render_inline(Admin::ToastComponent.new(message: "Moved to trash.", kind: :undo, action: { label: "Undo", url: "/undo", method: :post }))
    assert_selector ".admin-toast[data-admin--toast-timeout-value='8000'] form[action='/undo'] button", text: "Undo"
  end

  test "an error is an alert that stays until dismissed" do
    render_inline(Admin::ToastComponent.new(message: "Couldn't save.", kind: :error))
    assert_selector ".admin-toast[role=alert][data-admin--toast-timeout-value='0']"
    assert_selector ".admin-toast button[aria-label='Dismiss']"
  end

  test "a warning is an alert that stays until dismissed" do
    render_inline(Admin::ToastComponent.new(message: "Careful.", kind: :warning))
    assert_selector ".admin-toast[role=alert][data-admin--toast-timeout-value='0']"
  end

  test "the message is escaped" do
    render_inline(Admin::ToastComponent.new(message: "<b>x</b>"))
    assert_no_selector ".admin-toast b"
    assert_text "<b>x</b>"
  end

  test "an action may carry string keys, as it does after the session round trip" do
    render_inline(Admin::ToastComponent.new(message: "Moved.", kind: :undo, action: { "label" => "Undo", "url" => "/u", "method" => "post" }))
    assert_selector ".admin-toast form[action='/u'] button", text: "Undo"
  end

  test "an unknown kind is refused" do
    assert_raises(ArgumentError) { Admin::ToastComponent.new(message: "x", kind: :loud) }
  end
end

class Admin::ToastRegionComponentTest < ViewComponent::TestCase
  test "maps notice to success and alert to error, inside one live region" do
    render_inline(Admin::ToastRegionComponent.new(flash: { notice: "Done.", alert: "Failed." }))
    assert_selector "#toasts .admin-toast[role=status]", text: "Done."
    assert_selector "#toasts .admin-toast[role=alert]", text: "Failed."
  end

  test "a notice with an undo becomes an undo toast" do
    render_inline(Admin::ToastRegionComponent.new(flash: { notice: "Moved.", undo: { "label" => "Undo", "url" => "/u", "method" => "post" } }))
    assert_selector "#toasts .admin-toast form[action='/u']"
  end

  test "the region is rendered even when empty, so streams have a target" do
    render_inline(Admin::ToastRegionComponent.new(flash: {}))
    assert_selector "#toasts"
    assert_no_selector ".admin-toast"
  end

  test "a relay renders the toasts without the region" do
    render_inline(Admin::ToastRegionComponent.new(flash: { notice: "Done." }, relay: true))
    assert_no_selector "#toasts"
    assert_selector ".admin-toast", text: "Done."
  end
end
