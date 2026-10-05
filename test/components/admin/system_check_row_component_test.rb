require "test_helper"

class Admin::SystemCheckRowComponentTest < ViewComponent::TestCase
  def result(**overrides)
    Setup::SystemCheck::Result.new(**{ label: "Outgoing mail", status: :warning, message: "Password reset by email isn't configured.",
      command: Setup::SystemCheck::MAIL_FALLBACK_COMMAND }.merge(overrides))
  end

  test "a warning is a dot and the word Warning, with a warn border" do
    render_inline(Admin::SystemCheckRowComponent.new(result: result))

    assert_selector "li[data-status=warning] span.border-warn", text: "Warning"
    assert_selector "li span.bg-warn[aria-hidden=true]"
    assert_selector "p", text: "Outgoing mail"
  end

  test "an OK row is a dot and the word OK" do
    render_inline(Admin::SystemCheckRowComponent.new(result: result(status: :ok, command: nil)))

    assert_selector "li[data-status=ok] span", text: "OK"
    assert_selector "li span.bg-ok[aria-hidden=true]"
    assert_no_selector "code"
    assert_no_selector "button"
  end

  test "the command is escaped text and the Copy button copies it from the text value" do
    command = %(echo "<b>&" 'x')
    render_inline(Admin::SystemCheckRowComponent.new(result: result(command: command)))

    assert_selector "code", text: command
    assert_no_selector "code b"
    assert_equal command, page.find("[data-controller='admin--clipboard']")["data-admin--clipboard-text-value"]
    assert_selector "button[data-action='click->admin--clipboard#copy']", text: "Copy"
    assert_selector "[data-admin--clipboard-target=status][aria-live=polite]", visible: :all
  end

  test "not copyable (the setup wizard): the command shows but there is no Copy button or controller" do
    render_inline(Admin::SystemCheckRowComponent.new(result: result, copyable: false))

    assert_selector "code", text: Setup::SystemCheck::MAIL_FALLBACK_COMMAND
    assert_no_selector "button"
    assert_no_selector "[data-controller]"
  end

  test "a docs link shows only when there is one" do
    render_inline(Admin::SystemCheckRowComponent.new(result: result(docs: "https://example.org/mail")))
    assert_selector "a[href='https://example.org/mail']"

    render_inline(Admin::SystemCheckRowComponent.new(result: result))
    assert_no_selector "a"
  end
end
