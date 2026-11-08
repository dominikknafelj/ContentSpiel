require "test_helper"

class Admin::SettingsScreen::AiStateTest < ActiveSupport::TestCase
  AiState = Admin::SettingsScreen::AiState

  setup { @site = SiteSetting.instance }

  def with(provider:, key:)
    @site.update_columns(ai_provider: provider, ai_api_key: nil, ai_api_key_saved_at: nil)
    @site.update!(ai_api_key: "sk-ant-state-test") if key
    @site.reload
  end

  test "off without a provider, no key with one, key saved with a key" do
    assert_equal :off, AiState.of(with(provider: nil, key: false))
    assert_equal :off, AiState.of(with(provider: nil, key: true))
    assert_equal :no_key, AiState.of(with(provider: "anthropic", key: false))
    assert_equal :key_saved, AiState.of(with(provider: "anthropic", key: true))
  end

  test "a test's result gives connected or not connected, and each state has its tone" do
    site = with(provider: "anthropic", key: true)
    assert_equal :connected, AiState.of(site, result: :connected)
    assert_equal :not_connected, AiState.of(site, result: :failed)
    assert_raises(ArgumentError) { AiState.of(site, result: :maybe) }

    assert_equal %i[off no_key key_saved connected not_connected], AiState::STATES
    assert_equal({ off: :off, no_key: :warn, key_saved: :ok, connected: :ok, not_connected: :danger }, AiState::TONES)
    AiState::TONES.each_value { |tone| assert_includes Admin::Ui::StateChipComponent::TONES, tone }
    assert_equal [ "Off", "No key", "Key saved", "Connected", "Not connected" ], AiState::STATES.map { |state| AiState.word(state) }
  end
end
