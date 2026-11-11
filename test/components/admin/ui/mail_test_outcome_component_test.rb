require "test_helper"

class Admin::Ui::MailTestOutcomeComponentTest < ViewComponent::TestCase
  test "nothing sent yet draws the live region empty, for the answer" do
    render_inline(Admin::Ui::MailTestOutcomeComponent.new(address: "ada@example.com"))

    assert_selector "div[role=status].mt-2.empty\\:hidden", count: 1
    assert_equal "", page.find("div[role=status]", visible: :all).text.strip
  end

  test "a sent mail is the ok line, heard once through the region's status" do
    render_inline(Admin::Ui::MailTestOutcomeComponent.new(address: "ada@example.com", sent: true))

    assert_selector "div[role=status] > div.bg-ok-tint:not([role])", text: "Test mail sent to ada@example.com. Check your inbox."
  end

  test "a failure is the mail alert with the sentence and the server's line, and the region has no role of its own" do
    render_inline(Admin::Ui::MailTestOutcomeComponent.new(address: "ada@example.com", sent: false, alert: "The server refused the login.", line: "535 no"))

    assert_no_selector "div[role=status]"
    assert_selector "div.mt-2 > div[role=alert].border-warn", count: 1
    assert_selector "div[role=alert] p", text: "The server refused the login."
    assert_selector "div[role=alert] code", text: "535 no"
  end
end
