require "test_helper"

class Admin::Ui::ToastComponentTest < ViewComponent::TestCase
  test "success is a status that hides after four seconds" do
    render_inline(Admin::Ui::ToastComponent.new(message: "Saved."))
    assert_selector ".admin-toast[role=status][data-controller='admin--toast'][data-admin--toast-timeout-value='4000']", text: "Saved."
  end

  test "undo carries its action and stays eight seconds" do
    render_inline(Admin::Ui::ToastComponent.new(message: "Moved to trash.", kind: :undo, action: { label: "Undo", url: "/undo", method: :post }))
    assert_selector ".admin-toast[data-admin--toast-timeout-value='8000'] form[action='/undo'] button", text: "Undo"
  end

  test "an error is an alert that stays until dismissed" do
    render_inline(Admin::Ui::ToastComponent.new(message: "Couldn't save.", kind: :error))
    assert_selector ".admin-toast[role=alert][data-admin--toast-timeout-value='0']"
    assert_selector ".admin-toast button[aria-label='Dismiss']"
  end

  test "a warning is an alert that stays until dismissed" do
    render_inline(Admin::Ui::ToastComponent.new(message: "Careful.", kind: :warning))
    assert_selector ".admin-toast[role=alert][data-admin--toast-timeout-value='0']"
  end

  test "the message is escaped" do
    render_inline(Admin::Ui::ToastComponent.new(message: "<b>x</b>"))
    assert_no_selector ".admin-toast b"
    assert_text "<b>x</b>"
  end

  test "an action may carry string keys, as it does after the session round trip" do
    render_inline(Admin::Ui::ToastComponent.new(message: "Moved.", kind: :undo, action: { "label" => "Undo", "url" => "/u", "method" => "post" }))
    assert_selector ".admin-toast form[action='/u'] button", text: "Undo"
  end

  # A page-cache snapshot must never bring a toast back -- but not by way of
  # `data-turbo-temporary`: Turbo removes such an element from the *live*
  # page whenever it caches a snapshot, which a frame navigation promoted to
  # a history entry does too, deleting the toast that frame's response had
  # just relayed. `admin--toast` strips toasts from cached renders instead
  # (test/system/toast_test.rb: "going Back ... never brings its toast back").
  test "a toast is not data-turbo-temporary, which would delete a relayed toast as it appears" do
    render_inline(Admin::Ui::ToastComponent.new(message: "Moved.", kind: :undo, action: { label: "Undo", url: "/u" }))
    assert_selector ".admin-toast"
    assert_no_selector ".admin-toast[data-turbo-temporary]"
  end

  test "it has no id unless given one, and carries the one it is given" do
    render_inline(Admin::Ui::ToastComponent.new(message: "Saved."))
    assert_no_selector ".admin-toast[id]"

    render_inline(Admin::Ui::ToastComponent.new(message: "Couldn't save.", kind: :error, id: "toast-post"))
    assert_selector ".admin-toast#toast-post[role=alert]"
  end

  test "an unknown kind is refused" do
    assert_raises(ArgumentError) { Admin::Ui::ToastComponent.new(message: "x", kind: :loud) }
  end
end

class Admin::Ui::ToastRegionComponentTest < ViewComponent::TestCase
  test "maps notice to success and alert to error, inside one live region" do
    render_inline(Admin::Ui::ToastRegionComponent.new(flash: { notice: "Done.", alert: "Failed." }))
    assert_selector "#toasts .admin-toast[role=status]", text: "Done."
    assert_selector "#toasts .admin-toast[role=alert]", text: "Failed."
  end

  test "a notice with an undo becomes an undo toast" do
    render_inline(Admin::Ui::ToastRegionComponent.new(flash: { notice: "Moved.", undo: { "label" => "Undo", "url" => "/u", "method" => "post" } }))
    assert_selector "#toasts .admin-toast form[action='/u']"
  end

  # Final review C, I4: a bulk action that did some and refused or failed
  # others names the failures in its one toast; a 4 s success toast would take
  # them away before they could be read.
  test "a warning stays until dismissed, keeps its Undo, and is an alert" do
    render_inline(Admin::Ui::ToastRegionComponent.new(flash: { warning: "Moved 2 posts to the trash. 1 was refused: “A”.", undo: { "label" => "Undo", "url" => "/u", "method" => "post" } }))
    assert_selector "#toasts .admin-toast[role=alert][data-kind=warning][data-admin--toast-timeout-value='0']", text: "1 was refused"
    assert_selector "#toasts .admin-toast form[action='/u']"
  end

  test "the region is rendered even when empty, so streams have a target" do
    render_inline(Admin::Ui::ToastRegionComponent.new(flash: {}))
    assert_selector "#toasts"
    assert_no_selector ".admin-toast"
  end

  test "a relay renders the toasts without the region" do
    render_inline(Admin::Ui::ToastRegionComponent.new(flash: { notice: "Done." }, relay: true))
    assert_no_selector "#toasts"
    assert_selector ".admin-toast", text: "Done."
  end
end

# `toast_stream` (`Admin::AutosaveResponses`) is how a Turbo Stream answer --
# one with no redirect, so no flash -- raises a toast: one append to the
# layout's `#toasts`.
class Admin::Ui::ToastStreamTest < ViewComponent::TestCase
  class Responder
    include Admin::AutosaveResponses

    def initialize(view) = @view = view
    def turbo_stream = Turbo::Streams::TagBuilder.new(@view)
  end

  setup { @responder = Responder.new(vc_test_controller.view_context) }

  test "appends one toast to the toasts region" do
    stream = Capybara.string(@responder.toast_stream("Order restored."))
    assert_equal 1, stream.all("turbo-stream[action='append'][target='toasts']", visible: :all).size
    assert_includes @responder.toast_stream("Order restored."), "Order restored."
    assert_includes @responder.toast_stream("Order restored."), 'role="status"'
  end

  test "passes kind, action and id through to the toast" do
    html = @responder.toast_stream("Couldn't save your changes.", kind: :error, id: "toast-page")
    assert_includes html, 'id="toast-page"'
    assert_includes html, 'role="alert"'

    html = @responder.toast_stream("Moved.", kind: :undo, action: { label: "Undo", url: "/undo", method: :post })
    assert_includes html, 'action="/undo"'
    assert_includes html, 'data-kind="undo"'
  end
end
