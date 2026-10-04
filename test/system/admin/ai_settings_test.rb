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

    # Held open for as long as a test asks (`StubProvider.delay`), the cheapest honest way to keep a request in flight.
    class << self
      attr_accessor :delay
    end

    def test_connection
      sleep(self.class.delay.to_f)
      raise AI::Error, "The AI provider refused the API key." unless @api_key == KEY

      true
    end
  end

  setup do
    AI::Providers.register("test/stub", StubProvider)
    site_settings(:default).update!(setup_completed_at: Time.current, ai_provider: "test/stub")
    sign_in_via_form(users(:one))
  end

  teardown do
    StubProvider.delay = nil
    Rails.application.reloader.prepare!
  end

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
    # The markup can't show a value that was only typed, so the controls are asked too: the entry the key was typed
    # into is gone, and nothing on the page holds the key as its value.
    assert_no_selector "#settings-ai_api_key"
    assert_equal 0, page.evaluate_script("Array.from(document.querySelectorAll('input, textarea')).filter((control) => control.value.includes(#{KEY.to_json})).length")
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

  # Final wave B, ledger C-M8 and Task 7 minor 7: the main Save re-renders the
  # screen and dropped a typed key without a word; and Cancel / Save key left
  # the focus on <body>.
  test "a typed, unsaved key holds the main Save back; Cancel and Save key hand the focus on" do
    visit "/cs-studio/settings"
    await_admin_controllers

    fill_in "settings-ai_model", with: "another-model"
    assert_selector "#{footer} button[type=submit]:not([disabled])", text: "Save"
    # (The main form is unsaved now, so the key's own controls are locked;
    # put it back and open the entry.)
    fill_in "settings-ai_model", with: ""
    within("#settings-ai-key") { click_on "Add key" }
    fill_in "API key", with: KEY
    fill_in "settings-ai_model", with: "another-model"

    assert_selector "#{footer} button[type=submit][disabled]", text: "Save"
    assert_selector "#{footer} [role=status]", text: "Save or cancel the API key first."

    fill_in "settings-ai_model", with: ""
    within("#settings-ai-key") { click_on "Cancel" }
    assert_no_selector "#{footer} [role=status]", text: "Save or cancel the API key first."
    assert_equal "Add key", page.evaluate_script("document.activeElement.textContent.trim()")

    within("#settings-ai-key") { click_on "Add key" }
    fill_in "API key", with: KEY
    click_on "Save key"
    assert_selector "#toasts .admin-toast", text: "API key saved"
    assert_selector "#settings-ai-key [data-ai-key-state=set]"
    assert_no_selector "#{footer} [role=status]", text: "Save or cancel the API key first."
    assert_eventually { page.evaluate_script("document.activeElement.textContent.trim()") == "Replace" }
  end

  # Task 7 minor 11: a key write that lands while a Test is in flight replaces
  # the test's form; its end never reached the controller and the button
  # stayed disabled, with its spinner, until a reload.
  test "a key saved while a test is in flight leaves Test connection usable afterwards" do
    site_settings(:default).update!(ai_api_key: KEY)
    visit "/cs-studio/settings"
    await_admin_controllers
    StubProvider.delay = 1.0

    click_on "Test connection"
    assert_selector "button[disabled]", text: "Testing…"
    within("#settings-ai-key") { click_on "Replace" }
    fill_in "API key", with: KEY
    click_on "Save key"
    assert_selector "#toasts .admin-toast", text: "API key saved"

    assert_selector "button:not([disabled])", text: "Test connection", wait: 5
    assert_no_selector "button", text: "Testing…"
  end

  test "a wrong key shows the provider's message in Test connection" do
    site_settings(:default).update!(ai_api_key: "sk-ant-wrong")
    visit "/cs-studio/settings"
    await_admin_controllers

    click_on "Test connection"
    assert_selector "#settings-ai-test-result .text-danger-ink", text: "The AI provider refused the API key."
  end

  test "the test stays disabled for the whole flight, even when Model is edited and reverted during it" do
    site_settings(:default).update!(ai_api_key: KEY)
    StubProvider.delay = 1.5
    visit "/cs-studio/settings"
    await_admin_controllers

    click_on "Test connection"
    assert_selector "button[form='settings-ai-test-form'][disabled]"
    fill_in "Model", with: "claude-opus-5"
    fill_in "Model", with: ""
    # Back in line with the saved values, but the request is still out: no second provider call.
    assert_selector "button[form='settings-ai-test-form'][disabled]"
    assert_selector "#settings-ai-test-result", text: /CONNECTED/, wait: 10
    assert_no_selector "button[form='settings-ai-test-form'][disabled]"

    # Edited during a flight and left edited: it is still gated when the answer lands. The first test's
    # "CONNECTED" is still in the slot and the button is disabled during any flight, so neither says the second
    # answer has landed: the slot is emptied first, and the button is looked at only once it is no longer busy.
    page.execute_script("document.getElementById('settings-ai-test-result').replaceChildren()")
    assert_no_selector "#settings-ai-test-result", text: /CONNECTED/
    click_on "Test connection"
    fill_in "Model", with: "claude-opus-5"
    assert_selector "#settings-ai-test-result", text: /CONNECTED/, wait: 10
    assert_no_selector "button", text: "Testing…"
    assert_selector "button[form='settings-ai-test-form'][disabled]"
    assert_text "Save provider and model first. Tests the saved settings."
  end

  test "a change to another field disables Test connection with the pending hint, and reverting re-enables it" do
    site_settings(:default).update!(ai_api_key: KEY)
    visit "/cs-studio/settings"
    await_admin_controllers

    original = find_field("settings-trash_retention_days").value
    fill_in "settings-trash_retention_days", with: "9"
    assert_selector "button[form='settings-ai-test-form'][disabled]"
    assert_text "Save or cancel your changes first."
    assert_no_text "Save provider and model first."

    fill_in "settings-trash_retention_days", with: original
    assert_no_selector "button[form='settings-ai-test-form'][disabled]"
    assert_no_text "Save or cancel your changes first."
  end

  test "Save key with an empty input shows the error with the input still open, and Cancel clears it" do
    visit "/cs-studio/settings"
    await_admin_controllers

    within("#settings-ai-key") { click_on "Add key" }
    click_on "Save key"

    assert_selector "#settings-ai-key-errors", text: "Enter the API key first."
    assert_selector "#settings-ai_api_key[aria-invalid=true]"
    within("#settings-ai-key") { click_on "Cancel" }
    assert_no_selector "#settings-ai-key-errors", text: "Enter the API key first."
    within("#settings-ai-key") { click_on "Add key" }
    assert_no_selector "#settings-ai_api_key[aria-invalid]"
  end

  test "two key actions in a row, with no page load between them, both work" do
    visit "/cs-studio/settings"
    await_admin_controllers

    within("#settings-ai-key") { click_on "Add key" }
    fill_in "API key", with: KEY
    click_on "Save key"
    assert_selector "#settings-ai-key [data-ai-key-state=set]"
    within("#settings-ai-key") { click_on "Replace" }
    fill_in "API key", with: "sk-ant-second-key"
    click_on "Save key"
    assert_selector "#toasts .admin-toast", text: "API key saved", count: 2
    assert_equal "sk-ant-second-key", site_settings(:default).reload.ai_api_key
    click_on "Remove…"
    within("#settings-ai-remove-key-dialog") { click_on "Remove key" }
    assert_selector "#settings-ai-key", text: "No key yet"
  end
end
