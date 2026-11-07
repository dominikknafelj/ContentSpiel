require "test_helper"

# `Admin::Ui::ToastRegionComponent`: the layout's one `#toasts` live region,
# which draws the flash's toasts, or only the toasts for a frame's relay.
class Admin::Ui::ToastRegionComponentTest < ViewComponent::TestCase
  test "success and error: notice is a success toast and alert an error toast, inside one live region" do
    render_inline(Admin::Ui::ToastRegionComponent.new(flash: { notice: "Done.", alert: "Failed." }))
    assert_selector "#toasts .admin-toast[role=status]", text: "Done."
    assert_selector "#toasts .admin-toast[role=alert]", text: "Failed."
  end

  test "undo: a notice with an undo becomes an undo toast" do
    render_inline(Admin::Ui::ToastRegionComponent.new(flash: { notice: "Moved.", undo: { "label" => "Undo", "url" => "/u", "method" => "post" } }))
    assert_selector "#toasts .admin-toast form[action='/u']"
  end

  # A bulk action that did some and refused or failed others names the
  # failures in its one toast; a 4 s success toast would take them away
  # before they could be read.
  test "warning: a warning stays until dismissed, keeps its Undo, and is an alert" do
    render_inline(Admin::Ui::ToastRegionComponent.new(flash: { warning: "Moved 2 posts to the trash. 1 was refused: “A”.", undo: { "label" => "Undo", "url" => "/u", "method" => "post" } }))
    assert_selector "#toasts .admin-toast[role=alert][data-kind=warning][data-admin--ui--toast-timeout-value='0']", text: "1 was refused"
    assert_selector "#toasts .admin-toast form[action='/u']"
  end

  test "empty: the region is rendered even when empty, so streams have a target" do
    render_inline(Admin::Ui::ToastRegionComponent.new(flash: {}))
    assert_selector "#toasts"
    assert_no_selector ".admin-toast"
  end

  test "relay: a relay renders the toasts without the region" do
    render_inline(Admin::Ui::ToastRegionComponent.new(flash: { notice: "Done." }, relay: true))
    assert_no_selector "#toasts"
    assert_selector ".admin-toast", text: "Done."
  end
end
