require "test_helper"

# Translation helpers spec §6.2: the Settings module's "AI translation"
# section -- provider, model and an API key that is stored encrypted and
# never rendered, logged or audited; a blank key keeps the stored one,
# Remove key clears it, and Test connection reports OK or the provider's
# error inline.
class Admin::AISettingsTest < ActionDispatch::IntegrationTest
  KEY = "sk-ant-secret-0123456789abcdef".freeze

  # Registered for these tests only (the teardown re-runs `to_prepare`,
  # which resets the registry to the built-ins): answers `test_connection`
  # by its key, so a test picks OK or failure without any network.
  class StubProvider
    def initialize(api_key:, model:)
      @api_key = api_key
      @model = model
    end

    def test_connection
      raise AI::Error, "The AI provider refused the API key." unless @api_key == KEY

      true
    end
  end

  setup do
    AI::Providers.register("test/stub", StubProvider)
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
    @site = site_settings(:default)
  end

  teardown { Rails.application.reloader.prepare! }

  def save(params)
    patch "/cs-studio/settings", params: { site_setting: params, base_updated_at: @site.reload.updated_at.iso8601(6) }, as: :turbo_stream
  end

  def stored_ciphertext = SiteSetting.connection.select_value("select ai_api_key from site_settings where id = #{@site.id}")

  test "the section shows the provider choices, the model with its default as placeholder, and an empty key field" do
    get "/cs-studio/settings"

    assert_response :success
    assert_select "h2", "AI translation"
    assert_select "select[name='site_setting[ai_provider]'] option[value='anthropic']"
    assert_select "select[name='site_setting[ai_provider]'] option[value='test/stub']"
    assert_select "input[name='site_setting[ai_model]'][placeholder='claude-sonnet-5']"
    assert_select "input[type=password][name='site_setting[ai_api_key]']:not([value])"
    assert_select "button", text: "Remove key", count: 0
    assert_select "button", text: "Test connection"
  end

  test "provider and model autosave with the rest of the form" do
    save(title: "Test Site", ai_provider: "anthropic", ai_model: "claude-opus-5")

    assert_response :success
    assert_equal [ "anthropic", "claude-opus-5" ], [ @site.reload.ai_provider, @site.ai_model ]
  end

  test "an unregistered provider is refused with a per-field error" do
    save(ai_provider: "nobody/nothing")

    assert_response :unprocessable_entity
    assert_select_in_stream "settings-ai_provider-errors", /AI provider isn't an available provider/
    assert_nil @site.reload.ai_provider
  end

  test "the key is stored encrypted and the page never shows it" do
    save(ai_api_key: KEY)

    assert_response :success
    assert_equal KEY, @site.reload.ai_api_key
    assert_not_nil stored_ciphertext
    assert_not_includes stored_ciphertext, KEY
    assert_not_includes response.body, KEY
    # The key section comes back showing the key as set, its field empty.
    assert_select_in_stream "settings-ai-key-section", /API key: set/

    get "/cs-studio/settings"
    assert_not_includes response.body, KEY
    assert_select "#settings-ai-key-section", /API key: set/
    assert_select "input[type=password][name='site_setting[ai_api_key]']:not([value])"
    assert_select "button", text: "Remove key"
  end

  test "a re-render after a validation error never contains the key" do
    @site.update!(ai_api_key: KEY)

    save(title: "", ai_api_key: "sk-ant-other-key-typed-in")

    assert_response :unprocessable_entity
    assert_not_includes response.body, KEY
    assert_not_includes response.body, "sk-ant-other-key-typed-in"
    assert_equal KEY, @site.reload.ai_api_key
  end

  test "a blank key keeps the stored one" do
    @site.update!(ai_api_key: KEY)

    save(title: "Test Site", ai_api_key: "", ai_model: "claude-opus-5")

    assert_response :success
    assert_equal KEY, @site.reload.ai_api_key
    assert_equal "claude-opus-5", @site.ai_model
  end

  test "Remove key clears it" do
    @site.update!(ai_api_key: KEY)

    save(remove_ai_key: "1")

    assert_response :success
    assert_nil @site.reload.ai_api_key
    assert_select_in_stream "settings-ai-key-section", /No API key/
  end

  test "a newly typed key wins over Remove key in the same save" do
    @site.update!(ai_api_key: KEY)

    save(ai_api_key: "sk-ant-replacement", remove_ai_key: "1")

    assert_equal "sk-ant-replacement", @site.reload.ai_api_key
  end

  test "the audit event says the key changed, never what it is" do
    save(ai_api_key: KEY)

    event = Audit::Event.where(action: "settings.updated").order(:id).last
    assert_not_nil event
    assert_not event.snapshot.key?("ai_api_key")
    assert_not_includes event.snapshot.to_json, KEY
    assert_not_includes event.field_changes.to_json, KEY
    assert_equal [ "not set", "set" ], event.field_changes["AI key"]
  end

  test "the key is filtered from request logs" do
    filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
      .filter("site_setting" => { "ai_api_key" => KEY })

    assert_not_equal KEY, filtered.dig("site_setting", "ai_api_key")
  end

  test "the AI fields render once, untranslated, in another language too" do
    with_locales(%w[en de], default: "en")
    @site.reload.update!(ai_provider: "anthropic", ai_model: "claude-opus-5")

    get "/cs-studio/settings", params: { locale: "de" }

    assert_select "select[name='site_setting[ai_provider]']", count: 1
    assert_select "select[name='site_setting[ai_provider]'] option[selected][value='anthropic']"
    assert_select "input[name='site_setting[ai_model]'][value='claude-opus-5']", count: 1
  end

  test "Test connection shows OK" do
    @site.update!(ai_provider: "test/stub", ai_api_key: KEY)

    post "/cs-studio/settings/test_ai_connection", as: :turbo_stream

    assert_response :success
    assert_select_in_stream "settings-ai-test-result", /Connection OK/
  end

  test "Test connection shows the provider's error" do
    @site.update!(ai_provider: "test/stub", ai_api_key: "sk-ant-wrong")

    post "/cs-studio/settings/test_ai_connection", as: :turbo_stream

    assert_response :unprocessable_entity
    assert_select_in_stream "settings-ai-test-result", /refused the API key/
    assert_not_includes response.body, "sk-ant-wrong"
  end

  test "Test connection without a provider and key says what's missing" do
    post "/cs-studio/settings/test_ai_connection", as: :turbo_stream

    assert_response :unprocessable_entity
    assert_select_in_stream "settings-ai-test-result", /isn't set up/
  end

  test "Test connection needs settings.manage" do
    @site.update!(ai_provider: "test/stub", ai_api_key: KEY)
    sign_in_as(users(:author))

    post "/cs-studio/settings/test_ai_connection", as: :turbo_stream

    assert_response :forbidden
  end
end
