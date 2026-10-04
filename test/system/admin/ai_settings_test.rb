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

  def footer = ".admin-save-bar"

  test "adding, testing and removing the key; Test connection tests the saved settings" do
    visit "/cs-studio/settings"
    await_admin_controllers

    assert_selector "#settings-ai-key [data-ai-key-state=unset]", text: "No key yet"
    within("#settings-ai-key") { click_on "Add key" }
    fill_in "API key", with: KEY
    click_on "Save key"

    assert_selector "#toasts .admin-toast", text: "API key saved"
    assert_selector "#settings-ai-key [data-ai-key-state=set]", text: /Key saved · added \d{1,2} \w{3}/
    assert_not_includes page.html, KEY, "never rendered, not even in a hidden input or attribute"
    assert_equal KEY, site_settings(:default).reload.ai_api_key
    # The page and its state stay: no navigation happened, the footer is clean.
    assert_selector footer, text: /No unsaved changes/i

    # Test connection is on, and answers with the measured time.
    assert_no_selector "button[form='settings-ai-test-form'][disabled]"
    click_on "Test connection"
    assert_selector "#settings-ai-test-result", text: /CONNECTED · \d+ MS/

    # Change the model: the test is off with the specific hint; the key's controls wait too.
    fill_in "Model", with: "claude-opus-5"
    assert_selector "button[form='settings-ai-test-form'][disabled]"
    assert_text "Save provider and model first. Tests the saved settings."
    assert_selector "#settings-ai-key button[disabled]", text: "Replace"
    assert_selector "#settings-ai-key button[disabled]", text: "Remove…"
    assert_selector "#settings-ai-key", text: "Save or cancel your changes first."

    # Save the model: the test is available again, against the saved settings.
    click_on "Save"
    assert_selector "#toasts .admin-toast", text: "Settings saved"
    await_admin_controllers
    assert_no_selector "button[form='settings-ai-test-form'][disabled]"
    click_on "Test connection"
    assert_selector "#settings-ai-test-result", text: /CONNECTED · \d+ MS/

    # Remove… asks first.
    click_on "Remove…"
    within("#settings-ai-remove-key-dialog") { click_on "Remove key" }
    assert_selector "#settings-ai-key", text: "No key yet"
    assert_nil site_settings(:default).reload.ai_api_key
  end

  test "Replace opens the input empty and Cancel closes it" do
    site_settings(:default).update!(ai_api_key: KEY)
    visit "/cs-studio/settings"
    await_admin_controllers

    within("#settings-ai-key") { click_on "Replace" }
    assert_equal "", find_field("API key").value
    fill_in "API key", with: "half-typed"
    within("#settings-ai-key") { click_on "Cancel" }
    assert_selector "#settings-ai-key [data-ai-key-state=set]"
    assert_no_field "API key"
    within("#settings-ai-key") { click_on "Replace" }
    assert_equal "", find_field("API key").value
    assert_selector footer, text: /No unsaved changes/i
  end

  test "a wrong key shows the provider's message in Test connection" do
    site_settings(:default).update!(ai_api_key: "sk-ant-wrong")
    visit "/cs-studio/settings"
    await_admin_controllers

    click_on "Test connection"
    assert_selector "#settings-ai-test-result .text-danger-ink", text: "The AI provider refused the API key."
  end
end
