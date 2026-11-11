require "test_helper"

class Admin::Ui::MailAlertComponentTest < ViewComponent::TestCase
  test "the sentence in the compact warn alert, and the server's line in mono under it" do
    render_inline(Admin::Ui::MailAlertComponent.new(sentence: "The server refused the login.", line: "535 5.7.8 Authentication failed", class: "mt-2"))

    assert_selector "div[role=alert].rounded-card.border-warn.bg-warn-tint.text-warn-ink.mt-2", count: 1
    assert_selector "p", text: "The server refused the login."
    assert_selector "p.mt-1 code.font-cs-mono.break-words", text: "535 5.7.8 Authentication failed"
  end

  test "without a line it is the sentence alone" do
    render_inline(Admin::Ui::MailAlertComponent.new(sentence: "Mail could not be sent."))

    assert_selector "div[role=alert] p", count: 1, text: "Mail could not be sent."
    assert_no_selector "code"
  end

  test "the line is text: markup in it is escaped" do
    render_inline(Admin::Ui::MailAlertComponent.new(sentence: "Failed.", line: "<b>535</b>"))

    assert_no_selector "b"
    assert_selector "code", text: "<b>535</b>"
  end
end
