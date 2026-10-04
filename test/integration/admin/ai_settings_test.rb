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

  # The Settings form's own save (provider and model are fields of it; a 303
  # on success).
  def save(params)
    patch "/cs-studio/settings", params: { site_setting: params, base_updated_at: @site.reload.updated_at.iso8601(6) }
  end

  # The key's own instant actions (`PATCH` / `DELETE /settings/ai_key`, Turbo
  # Stream answers, `Admin::AiKeysController`): the key is never a field of the
  # Settings form. Both carry the main form's base, as the real forms do.
  def save_key(key)
    patch "/cs-studio/settings/ai_key", params: { site_setting: { ai_api_key: key }, main_base_updated_at: @site.reload.updated_at.iso8601(6) }, as: :turbo_stream
  end

  def remove_key
    delete "/cs-studio/settings/ai_key", params: { main_base_updated_at: @site.reload.updated_at.iso8601(6) }, as: :turbo_stream
  end

  # A stored key the current encryption keys can't decrypt -- keys lost or
  # rotated, or production booted without them. Raw SQL: anything through
  # the model would encrypt this string properly.
  def corrupt_stored_key!
    SiteSetting.connection.execute(%q(update site_settings set ai_api_key = '{"p":"garbage","h":{"iv":"x","at":"y"}}'))
    Current.site = nil
    @site = SiteSetting.find(@site.id)
  end

  def stored_ciphertext = SiteSetting.connection.select_value("select ai_api_key from site_settings where id = #{@site.id}")

  test "the section shows the provider choices, the model with its default as placeholder, and an empty key field" do
    get "/cs-studio/settings"

    assert_response :success
    assert_select "h2", "AI translation"
    assert_select "select[name='site_setting[ai_provider]'] option[value='anthropic']"
    assert_select "select[name='site_setting[ai_provider]'] option[value='test/stub']"
    assert_select "input[name='site_setting[ai_model]'][placeholder='claude-sonnet-5']"
    assert_select "input[type=password][name='site_setting[ai_api_key]'][form='settings-ai-key-form']:not([value])"
    assert_select "#settings-ai-key button", text: "Remove…", count: 0
    assert_select "#settings-ai-key button", text: "Add key"
    assert_select "button[form='settings-ai-test-form']", text: "Test connection"
    # Provider and model are fields of the one form; the key is not.
    assert_select "form#settings-form select[name='site_setting[ai_provider]']"
    assert_select "form#settings-form input[name='site_setting[ai_model]']"
    assert_select "form#settings-form input[name='site_setting[ai_api_key]']:not([form='settings-ai-key-form'])", count: 0
    # What the client compares to gate Test connection: the SAVED values.
    assert_select "select[name='site_setting[ai_provider]'][data-saved-value='']"
    assert_select "input[name='site_setting[ai_model]'][data-saved-value='']"
  end

  # -- the chip (D11) -----------------------------------------------------------

  test "no key reads No key yet, with Add key" do
    get "/cs-studio/settings"

    assert_select "#settings-ai-key [data-ai-key-state=unset]", /No key yet/
    assert_select "#settings-ai-key button", text: "Add key"
  end

  test "a key saved before the date column existed reads Key saved alone" do
    @site.update!(ai_api_key: KEY)
    @site.update_columns(ai_api_key_saved_at: nil)

    get "/cs-studio/settings"

    assert_select "#settings-ai-key [data-ai-key-state=set]" do |chip|
      assert_equal "● Key saved", chip.text.squish
    end
    assert_select "#settings-ai-key button", text: "Replace"
    assert_select "#settings-ai-key button", text: "Remove…"
  end

  test "a key saved this year reads the day and month, last year's also the year" do
    @site.update!(ai_api_key: KEY)
    @site.update_columns(ai_api_key_saved_at: Time.zone.local(Time.zone.today.year, 10, 2, 12))
    get "/cs-studio/settings"
    assert_select "#settings-ai-key [data-ai-key-state=set]" do |chip|
      assert_equal "● Key saved · added 2 Oct", chip.text.squish
    end

    @site.update_columns(ai_api_key_saved_at: Time.zone.local(Time.zone.today.year - 1, 10, 2, 12))
    get "/cs-studio/settings"
    assert_select "#settings-ai-key [data-ai-key-state=set]" do |chip|
      assert_equal "● Key saved · added 2 Oct #{Time.zone.today.year - 1}", chip.text.squish
    end
  end

  test "Test connection is gated by the client on the saved provider and model" do
    @site.update!(ai_provider: "anthropic", ai_model: "claude-opus-5")

    get "/cs-studio/settings"

    assert_select "select[name='site_setting[ai_provider]'][data-saved-value='anthropic']"
    assert_select "input[name='site_setting[ai_model]'][data-saved-value='claude-opus-5']"
  end

  test "provider and model are saved with the rest of the form" do
    save(ai_provider: "anthropic", ai_model: "claude-opus-5")

    assert_response :see_other
    assert_equal [ "anthropic", "claude-opus-5" ], [ @site.reload.ai_provider, @site.ai_model ]
  end

  test "an unregistered provider is refused with a per-field error" do
    save(ai_provider: "nobody/nothing")

    assert_response :unprocessable_entity
    assert_select ".admin-error-summary a[href='#settings-ai_provider']", /AI provider isn't an available provider/
    assert_select "#settings-ai_provider-errors", /AI provider isn't an available provider/
    assert_nil @site.reload.ai_provider
  end

  test "the key is stored encrypted and the page never shows it" do
    save_key(KEY)

    assert_response :success
    assert_equal KEY, @site.reload.ai_api_key
    assert_not_nil stored_ciphertext
    assert_not_includes stored_ciphertext, KEY
    assert_not_includes response.body, KEY
    # The key section comes back showing the key as set, its field empty.
    assert_select_in_stream "settings-ai-key", /Key saved · added/
    assert_not_nil @site.ai_api_key_saved_at
    assert_select "turbo-stream[action=append][target=toasts]", /API key saved/
    # Only the key component and its forms are replaced: the main form's fields are left alone.
    assert_select "turbo-stream[action=replace]" do |streams|
      assert_equal %w[settings-ai-key settings-ai-key-forms settings-base-updated-at], streams.map { |stream| stream["target"] }.sort
    end
    # The main form's base moves with the key write, or its next Save would look stale.
    assert_select "turbo-stream[target='settings-base-updated-at'] input[value=?]", @site.updated_at.iso8601(6)

    get "/cs-studio/settings"
    assert_not_includes response.body, KEY
    assert_select "#settings-ai-key [data-ai-key-state=set]"
    assert_select "input[type=password][name='site_setting[ai_api_key]']:not([value])"
    assert_select "#settings-ai-key button", text: "Remove…"
  end

  test "a blank key is refused in the key component and nothing changes" do
    @site.update!(ai_api_key: KEY)
    before = @site.reload.updated_at

    save_key("")

    assert_response :unprocessable_entity
    assert_select_in_stream "settings-ai-key", /Enter the API key first/
    assert_select "turbo-stream[target='settings-base-updated-at']", count: 0
    assert_equal KEY, @site.reload.ai_api_key
    assert_equal before, @site.updated_at
  end

  test "a key save from a user without settings.manage is refused" do
    sign_in_as(users(:author))

    save_key(KEY)

    assert_response :forbidden
    assert_nil @site.reload.ai_api_key
  end

  test "a re-render after a validation error never contains the key, and a key posted to the form is ignored" do
    @site.update!(ai_api_key: KEY)

    patch "/cs-studio/settings", params: { site_setting: { translations: { en: { title: "" } }, ai_api_key: "sk-ant-other-key-typed-in" },
      base_updated_at: @site.reload.updated_at.iso8601(6) }

    assert_response :unprocessable_entity
    assert_not_includes response.body, KEY
    assert_not_includes response.body, "sk-ant-other-key-typed-in"
    assert_equal KEY, @site.reload.ai_api_key
  end

  test "the main Save keeps the stored key" do
    @site.update!(ai_api_key: KEY)

    save(ai_model: "claude-opus-5")
    assert_response :see_other
    assert_equal KEY, @site.reload.ai_api_key
    assert_equal "claude-opus-5", @site.ai_model
  end

  test "Remove clears the key and the date" do
    @site.update!(ai_api_key: KEY)

    remove_key

    assert_response :success
    assert_nil @site.reload.ai_api_key
    assert_nil @site.ai_api_key_saved_at
    assert_select_in_stream "settings-ai-key", /No key yet/
    assert_select "turbo-stream[action=append][target=toasts]", /API key removed/
  end

  test "Remove key asks first, in the confirm dialog" do
    @site.update!(ai_api_key: KEY)

    get "/cs-studio/settings"

    assert_select "#settings-ai-key button[type=button]", text: "Remove…"
    # The dialog's form can't sit inside the Settings form: it is a sibling.
    assert_select "form#settings-form dialog", count: 0
    assert_select "#settings-ai-key-forms dialog#settings-ai-remove-key-dialog", /Remove the API key\?/ do
      assert_select "form[action='/cs-studio/settings/ai_key'] input[type=hidden][name='_method'][value='delete']"
      assert_select "form input[type=hidden][name='main_base_updated_at']"
      assert_select "button[type=submit]", text: "Remove key"
    end
  end

  test "a stored key that can't be decrypted still shows as set, and can be removed" do
    @site.update!(ai_api_key: KEY)
    corrupt_stored_key!

    get "/cs-studio/settings"
    assert_response :success
    assert_select "#settings-ai-key [data-ai-key-state=set]"

    save(ai_model: "still-editable")
    assert_response :see_other

    remove_key
    assert_response :success
    assert_nil stored_ciphertext
    assert_select_in_stream "settings-ai-key", /No key yet/
    event = Audit::Event.where(action: "settings.updated").order(:id).last
    assert_equal [ "set", "not set" ], event.field_changes["AI key"]
  end

  test "a stored key that can't be decrypted can be replaced" do
    @site.update!(ai_api_key: KEY)
    corrupt_stored_key!

    save_key("sk-ant-replacement")

    assert_response :success
    assert_equal "sk-ant-replacement", SiteSetting.find(@site.id).ai_api_key
  end

  test "Test connection with an unreadable stored key says to enter it again" do
    @site.update!(ai_provider: "test/stub", ai_api_key: KEY)
    corrupt_stored_key!

    post "/cs-studio/settings/test_ai_connection", as: :turbo_stream

    assert_response :unprocessable_entity
    assert_select_in_stream "settings-ai-test-result", /can't be read/
  end

  test "the audit event says the key changed, never what it is" do
    save_key(KEY)

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
    assert_select_in_stream "settings-ai-test-result", /● CONNECTED · \d+ MS/
    assert_not_includes response.body, KEY
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

  test "Test connection and the key actions need settings.manage, not just languages.manage" do
    user = users(:editor_branch)
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "languages.manage", scope: {})
    AccessControl::Membership.create!(user: user, group: access_control_groups(:branch_editors)) unless user.groups.exists?(access_control_groups(:branch_editors).id)
    sign_in_as(user)

    post "/cs-studio/settings/test_ai_connection", as: :turbo_stream
    assert_response :forbidden
    save_key(KEY)
    assert_response :forbidden
    remove_key
    assert_response :forbidden
  end

  test "Test connection needs settings.manage" do
    @site.update!(ai_provider: "test/stub", ai_api_key: KEY)
    sign_in_as(users(:author))

    post "/cs-studio/settings/test_ai_connection", as: :turbo_stream

    assert_response :forbidden
  end
end
