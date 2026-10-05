require "test_helper"

class Admin::SettingsScreen::AiTestResultComponentTest < ViewComponent::TestCase
  test "empty until a test ran, but the slot is there for the stream to replace" do
    render_inline Admin::SettingsScreen::AiTestResultComponent.new

    assert_selector "#settings-ai-test-result[role=status]"
    assert_no_text(/./)
  end

  test "connected: the time in ok ink and mono" do
    render_inline Admin::SettingsScreen::AiTestResultComponent.new(milliseconds: 412)

    assert_selector "#settings-ai-test-result .text-ok-ink.font-cs-mono", text: "● CONNECTED · 412 MS"
  end

  test "failed: the provider's message in danger ink" do
    render_inline Admin::SettingsScreen::AiTestResultComponent.new(message: "The AI provider refused the API key.")

    assert_selector "#settings-ai-test-result .text-danger-ink", text: "The AI provider refused the API key."
    assert_no_text "CONNECTED"
  end
end
