require "application_system_test_case"

# Translation helpers spec §6.2, in a real browser: the API key is saved by
# its own button (not the settings form's autosave), comes back as "API
# key: set" with an empty field, and Test connection answers inline. The
# provider is a stub registered for this test -- the app server runs in
# this process, so it sees the same registry -- and never reaches the
# network.
class Admin::AISettingsSystemTest < ApplicationSystemTestCase
  KEY = "sk-ant-system-test-key".freeze

  class StubProvider
    def initialize(api_key:, model:)
      @api_key = api_key
    end

    def test_connection
      raise AI::Error, "The AI provider refused the API key." unless @api_key == KEY

      true
    end
  end

  setup do
    AI::Providers.register("test/stub", StubProvider)
    site_settings(:default).update!(setup_completed_at: Time.current, ai_provider: "test/stub")
    sign_in_via_form(users(:one))
  end

  teardown { Rails.application.reloader.prepare! }

  test "saving, testing and removing the key" do
    visit "/cs-studio/settings"
    await_admin_controllers

    assert_text "No API key"
    fill_in "API key", with: KEY
    click_on "Save key"

    assert_selector "#settings-ai-key-section", text: "API key: set"
    assert_equal "", find_field("Replace API key").value
    assert_no_text KEY
    assert_not_includes page.html, KEY, "never rendered, not even in a hidden input or attribute"
    assert_equal KEY, site_settings(:default).reload.ai_api_key

    click_on "Test connection"
    assert_selector "#settings-ai-test-result", text: "Connection OK."

    click_on "Remove key"
    within("#settings-ai-remove-key-dialog") { click_on "Remove key" }
    assert_selector "#settings-ai-key-section", text: "No API key"
    assert_nil site_settings(:default).reload.ai_api_key
  end
end
