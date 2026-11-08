require "test_helper"

class Admin::SettingsScreen::AiTestResultComponentTest < ViewComponent::TestCase
  test "empty until a test ran, but the slot is there for the stream to replace" do
    render_inline Admin::SettingsScreen::AiTestResultComponent.new

    assert_selector "#settings-ai-test-result[role=status]"
    assert_no_text(/./)
  end

  test "connected: the ok state chip, Connected and the time, in the sans" do
    render_inline Admin::SettingsScreen::AiTestResultComponent.new(milliseconds: 412)

    assert_selector "#settings-ai-test-result .admin-state-chip[data-state-tone=ok]", text: "Connected · 412 ms"
    assert_no_selector ".font-cs-mono"
  end

  test "failed: Not connected, with the provider's message under it in danger ink" do
    render_inline Admin::SettingsScreen::AiTestResultComponent.new(message: "The AI provider refused the API key.")

    assert_selector "#settings-ai-test-result .admin-state-chip[data-state-tone=danger]", text: "Not connected"
    assert_selector "#settings-ai-test-result p.text-danger-ink", text: "The AI provider refused the API key."
    assert_no_text "Connected ·"
  end

  test "its words are keys" do
    assert_equal "Connected", I18n.t("admin.components.settings_screen.ai_state.connected")
    I18n.backend.store_translations(:en, admin: { components: { settings_screen: {
      ai_state: { connected: "Linked up" }, ai_test_result: { time: "%{milliseconds} msec" }
    } } })
    render_inline Admin::SettingsScreen::AiTestResultComponent.new(milliseconds: 7)

    assert_selector ".admin-state-chip", text: "Linked up · 7 msec"
  ensure
    I18n.backend.store_translations(:en, admin: { components: { settings_screen: {
      ai_state: { connected: "Connected" }, ai_test_result: { time: "%{milliseconds} ms" }
    } } })
  end
end
