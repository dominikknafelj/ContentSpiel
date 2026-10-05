require "test_helper"

class Admin::SettingsScreen::AiCardComponentTest < ViewComponent::TestCase
  def render_card(submitted: nil, **options)
    values = Admin::SettingsScreen::Values.new(site: SiteSetting.instance, submitted: submitted)
    render_inline Admin::SettingsScreen::AiCardComponent.new(site_setting: SiteSetting.instance, values: values, **options)
  end

  test "provider and model carry their saved values for the client's Test connection gate" do
    SiteSetting.instance.update!(ai_provider: "anthropic", ai_model: "claude-opus-5")
    render_card(submitted: ActionController::Parameters.new(ai_model: "typed-model").permit!)

    assert_selector "section#settings-ai-card[data-controller='admin--ai-settings admin--pending-lock']"
    assert_selector "select[name='site_setting[ai_provider]'][data-saved-value='anthropic']"
    # Typed beats stored in the field, but the saved value stays the stored one.
    assert_selector "input[name='site_setting[ai_model]'][value='typed-model'][data-saved-value='claude-opus-5']"
  end

  test "Test connection is a button of its own form, not a pending-lock control, with a hint slot and a result slot" do
    render_card

    assert_selector "button[type=submit][form='settings-ai-test-form'][data-admin--ai-settings-target=test]", text: "Test connection"
    assert_no_selector "button[form='settings-ai-test-form'][data-admin--pending-lock-target]"
    assert_selector "[data-admin--ai-settings-target=testHint][hidden]", visible: :all
    assert_selector "#settings-ai-test-result"
  end

  test "renders the key component and the per-field errors" do
    render_card(provider_errors: [ "AI provider isn't an available provider" ], model_errors: [ "Model is bad" ])

    assert_selector "#settings-ai-key"
    assert_selector "#settings-ai_provider-errors", text: "isn't an available provider"
    assert_selector "#settings-ai_model-errors", text: "Model is bad"
  end
end
