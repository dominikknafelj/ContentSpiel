require "test_helper"

class Admin::SettingsScreen::AiKeyComponentTest < ViewComponent::TestCase
  def render_key(site: SiteSetting.instance, error: nil)
    render_inline Admin::SettingsScreen::AiKeyComponent.new(site_setting: site, error: error)
  end

  def site_with_key(saved_at)
    site = SiteSetting.instance
    site.update!(ai_api_key: "sk-ant-component-test")
    site.update_columns(ai_api_key_saved_at: saved_at)
    site.reload
  end

  test "no key: No key yet, Add key, the entry hidden" do
    site = SiteSetting.instance
    site.update_columns(ai_api_key: nil, ai_api_key_saved_at: nil)
    render_key(site: site.reload)

    assert_selector "#settings-ai-key [data-ai-key-state=unset]", text: "No key yet"
    assert_selector "button", text: "Add key"
    assert_no_selector "button", text: "Remove…"
    assert_selector "[data-admin--settings--ai-target=entry][hidden]", visible: :all
  end

  test "a key without a date reads Key saved alone, with Replace and Remove…" do
    render_key(site: site_with_key(nil))

    assert_selector "[data-ai-key-state=set]", text: /\A\s*●\s*Key saved\s*\z/
    assert_selector "button", text: "Replace"
    assert_selector "button[data-action*='dialog']", text: "Remove…"
  end

  test "the date is day and month this year, with the year otherwise" do
    render_key(site: site_with_key(Time.zone.local(Time.zone.today.year, 10, 2, 12)))
    assert_selector "[data-ai-key-state=set]", text: "Key saved · added 2 Oct"
    assert_no_selector "[data-ai-key-state=set]", text: Time.zone.today.year.to_s

    render_key(site: site_with_key(Time.zone.local(2020, 10, 2, 12)))
    assert_selector "[data-ai-key-state=set]", text: "Key saved · added 2 Oct 2020"
  end

  test "the input belongs to the key's own form, is never pre-filled, and the key never appears" do
    render_key(site: site_with_key(nil))

    assert_selector "input[type=password][name='site_setting[ai_api_key]'][form='settings-ai-key-form']:not([value])", visible: :all
    assert_selector "button[type=submit][form='settings-ai-key-form']", text: "Save key", visible: :all
    assert_not_includes rendered_content, "sk-ant-component-test"
  end

  test "its controls are pending-lock controls" do
    render_key(site: site_with_key(nil))

    %w[Replace Remove…].each { |label| assert_selector "button[data-admin--saving--pending-lock-target=control]", text: label }
    assert_selector "input[data-admin--saving--pending-lock-target=control]", visible: :all
    assert_selector "button[data-admin--saving--pending-lock-target=control]", text: "Save key", visible: :all
    assert_selector "[data-admin--saving--pending-lock-target=hint]", visible: :all
  end

  test "an error shows in the slot with the input open" do
    render_key(error: "Enter the API key first.")

    assert_selector "#settings-ai-key-errors", text: "Enter the API key first."
    assert_no_selector "[data-admin--settings--ai-target=entry][hidden]", visible: :all
    assert_selector "[data-admin--settings--ai-target=chip][hidden]", visible: :all
    assert_selector "input[aria-invalid=true]"
  end
end
