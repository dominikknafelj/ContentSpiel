require "test_helper"

class Admin::SettingsTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
    @site = site_settings(:default)
  end

  test "shows the current title, tagline and default language" do
    @site.update!(title: "Dana's Notes", tagline: "Things I learned")

    get "/cs-studio/settings"
    assert_response :success
    assert_select "input[name='site_setting[title]'][value=?]", "Dana's Notes"
    assert_select "input[name='site_setting[tagline]'][value=?]", "Things I learned"
    assert_select "select[name='site_setting[default_locale]'] option[selected][value=?]", "en"
  end

  test "saving title and tagline answers a saved status stream" do
    patch "/cs-studio/settings", params: { site_setting: { title: "New Title", tagline: "New Tagline" },
      base_updated_at: @site.updated_at.iso8601(6) }, as: :turbo_stream

    assert_response :success
    assert_match(/Saved \d\d:\d\d/, response.body)
    assert_equal "New Title", @site.reload.title
    assert_equal "New Tagline", @site.tagline
  end

  test "a blank title comes back as a per-field error and doesn't save" do
    patch "/cs-studio/settings", params: { site_setting: { title: "" }, base_updated_at: @site.updated_at.iso8601(6) }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_select_in_stream "settings-title-errors", /can't be blank/
    assert_not_equal "", @site.reload.title
  end

  test "uploading a logo attaches it, and an untouched file field on a later save leaves it attached" do
    patch "/cs-studio/settings", params: { site_setting: { logo: fixture_file_upload("tiny.png", "image/png") },
      base_updated_at: @site.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success
    assert @site.reload.logo.attached?

    # A blank file field is what every autosave resends for every field the
    # editor didn't just touch (Rack parses an untouched file input as an
    # empty string) -- it must never be read as "detach the logo" the way a
    # raw `has_one_attached` writer would (the same bug class `Admin::
    # PagesController`'s own `hero_image` guards against).
    patch "/cs-studio/settings", params: { site_setting: { title: "Still here", logo: "" },
      base_updated_at: @site.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success
    assert @site.reload.logo.attached?
  end

  test "the explicit remove checkbox detaches the logo" do
    @site.logo.attach(io: File.open(file_fixture("tiny.png")), filename: "tiny.png", content_type: "image/png")
    assert @site.logo.attached?

    patch "/cs-studio/settings", params: { site_setting: { remove_logo: "1" }, base_updated_at: @site.updated_at.iso8601(6) }, as: :turbo_stream

    assert_response :success
    assert_not @site.reload.logo.attached?
  end

  test "social link rows drop half-filled entries and blank ones" do
    patch "/cs-studio/settings", params: { site_setting: {
      social_links: [
        { name: "GitHub", url: "https://github.com/dana" },
        { name: "Mastodon", url: "" },
        { name: "", url: "https://example.org" },
        { name: "", url: "" }
      ]
    }, base_updated_at: @site.updated_at.iso8601(6) }, as: :turbo_stream

    assert_response :success
    assert_equal({ "GitHub" => "https://github.com/dana" }, @site.reload.social_links)
  end

  test "a social link without a scheme is refused with a message, not dropped" do
    patch "/cs-studio/settings", params: { site_setting: {
      social_links: [ { name: "GitHub", url: "github.com/dana" } ]
    }, base_updated_at: @site.updated_at.iso8601(6) }, as: :turbo_stream

    assert_includes response.body, "must start with https://, http:// or mailto:"
    assert_equal({}, @site.reload.social_links.to_h)
  end

  test "the default language is restricted to the site's own enabled languages" do
    get "/cs-studio/settings"
    assert_select "select[name='site_setting[default_locale]'] option", 3
    assert_select "select[name='site_setting[default_locale]'] option[value='fr']", count: 0

    patch "/cs-studio/settings", params: { site_setting: { default_locale: "fr" }, base_updated_at: @site.updated_at.iso8601(6) }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_select_in_stream "settings-default_locale-errors", /must be one of the enabled languages/
    assert_equal "en", @site.reload.default_locale
  end

  test "a settings.manage user can set the trash retention period" do
    get "/cs-studio/settings"
    assert_response :success
    assert_select "input[type='number'][name='site_setting[trash_retention_days]'][value=?]", "30"

    patch "/cs-studio/settings", params: { site_setting: { trash_retention_days: 7 },
      base_updated_at: @site.updated_at.iso8601(6) }, as: :turbo_stream

    assert_response :success
    assert_equal 7, @site.reload.trash_retention_days
  end

  test "a negative trash retention period shows the validation error" do
    patch "/cs-studio/settings", params: { site_setting: { trash_retention_days: -1 },
      base_updated_at: @site.updated_at.iso8601(6) }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_select_in_stream "settings-trash_retention_days-errors", /must be greater than or equal to 0/
    assert_equal 30, @site.reload.trash_retention_days
  end

  # Dashboard spec §5: the site's own time zone, same autosave shape as
  # `trash_retention_days` above.
  test "a settings.manage user can set the site time zone" do
    get "/cs-studio/settings"
    assert_response :success
    assert_select "select[name='site_setting[time_zone]'] option[selected][value=?]", "UTC"

    patch "/cs-studio/settings", params: { site_setting: { time_zone: "Berlin" },
      base_updated_at: @site.updated_at.iso8601(6) }, as: :turbo_stream

    assert_response :success
    assert_equal "Berlin", @site.reload.time_zone
  end

  test "an unknown time zone shows the validation error" do
    patch "/cs-studio/settings", params: { site_setting: { time_zone: "Mars/Olympus" },
      base_updated_at: @site.updated_at.iso8601(6) }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_select_in_stream "settings-time_zone-errors", /isn't a known time zone/
    assert_equal "UTC", @site.reload.time_zone
  end

  # Final fix wave I2: autosave resends the whole form, so whatever the
  # select shows as selected is what a title-only edit writes back. A
  # stored value no option matched used to fall through to the first
  # option ("International Date Line West") and get saved as that.
  test "a stored zone no option names stays selected, and a title-only autosave keeps it" do
    @site.update_column(:time_zone, "America/Argentina/Cordoba")

    get "/cs-studio/settings"
    assert_response :success
    selected = css_select("select[name='site_setting[time_zone]'] option[selected]")
    assert_equal [ "America/Argentina/Cordoba" ], selected.map { |option| option["value"] }

    patch "/cs-studio/settings", params: { site_setting: { title: "Retitled", time_zone: selected.first["value"] },
      base_updated_at: @site.reload.updated_at.iso8601(6) }, as: :turbo_stream

    assert_response :success
    assert_equal "Retitled", @site.reload.title
    assert_equal "America/Argentina/Cordoba", @site.time_zone
  end

  test "a stored IANA identifier shows as its Rails zone and saves as it" do
    @site.update_column(:time_zone, "Europe/Berlin")

    get "/cs-studio/settings"
    selected = css_select("select[name='site_setting[time_zone]'] option[selected]").map { |option| option["value"] }
    assert_equal 1, selected.size

    patch "/cs-studio/settings", params: { site_setting: { title: "Retitled", time_zone: selected.first },
      base_updated_at: @site.reload.updated_at.iso8601(6) }, as: :turbo_stream

    assert_response :success
    assert_equal "Europe/Berlin", @site.reload.effective_time_zone.tzinfo.name
  end

  test "a stale save is reported instead of silently overwriting a newer one" do
    patch "/cs-studio/settings", params: { site_setting: { title: "First" }, base_updated_at: @site.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success

    patch "/cs-studio/settings", params: { site_setting: { title: "Second, from a stale tab" }, base_updated_at: @site.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success
    assert_match(/Changed elsewhere/, response.body)
  end

  # -- translated title and tagline (translation helpers spec §5) --

  def translate_site(title:, tagline: nil, locale: "de")
    Mobility.with_locale(locale) { @site.update!(title: title, tagline: tagline) }
  end

  test "in another language the title and tagline show that language's value beside the English original" do
    with_locales(%w[en de es], default: "en")
    @site.reload.update!(title: "Dana's Notes", tagline: "Things I learned")
    translate_site(title: "Danas Notizen")

    get "/cs-studio/settings", params: { locale: "de" }

    assert_response :success
    assert_select "input[name='site_setting[title]'][value=?]", "Danas Notizen"
    assert_select "input[name='site_setting[tagline]']" do |inputs|
      assert_nil inputs.first["value"].presence
    end
    assert_select "[data-original-for='title']", text: "Dana's Notes"
    assert_select "[data-original-for='tagline']", text: "Things I learned"
    assert_select "[data-translate-slot='title']"
    # The language switcher, keeping the editing language in the form's URL.
    assert_select "nav.admin-language-switcher a[href='/cs-studio/settings']", text: "English"
    assert_select "nav.admin-language-switcher a[href='/cs-studio/settings?locale=es']", text: "Español"
    assert_select "nav.admin-language-switcher [aria-current]", text: "Deutsch"
    assert_select "form[action='/cs-studio/settings?locale=de']"
    assert_select "##{Admin::SettingsFormComponent::DOM_ID} form"
    # Untranslated settings render once, the same in every language.
    assert_select "select[name='site_setting[default_locale]']", 1
    assert_select "select[name='site_setting[time_zone]']", 1
    assert_select "input[name='site_setting[trash_retention_days]']", 1
  end

  test "the default language shows no original" do
    with_locales(%w[en de], default: "en")

    get "/cs-studio/settings"

    assert_response :success
    assert_select "[data-original-for='title']", count: 0
    assert_select "[data-original-for='tagline']", count: 0
  end

  test "saving in German writes only the German title and tagline" do
    with_locales(%w[en de], default: "en")
    @site.reload.update!(title: "Dana's Notes", tagline: "Things I learned")

    patch "/cs-studio/settings", params: { locale: "de", site_setting: { title: "Danas Notizen", tagline: "Was ich gelernt habe" },
      base_updated_at: @site.reload.updated_at.iso8601(6) }, as: :turbo_stream

    assert_response :success
    @site.reload
    assert_equal({ "en" => "Dana's Notes", "de" => "Danas Notizen" }, @site.read_attribute(:title))
    assert_equal({ "en" => "Things I learned", "de" => "Was ich gelernt habe" }, @site.read_attribute(:tagline))
    event = Audit::Event.where(action: "settings.updated").order(:id).last
    assert_equal [ nil, "Danas Notizen" ], event.field_changes["de title"]
  end

  test "a blank German title is fine: only the default language's title is required" do
    with_locales(%w[en de], default: "en")
    translate_site(title: "Danas Notizen")

    patch "/cs-studio/settings", params: { locale: "de", site_setting: { title: "" },
      base_updated_at: @site.reload.updated_at.iso8601(6) }, as: :turbo_stream

    assert_response :success
    assert_equal({ "en" => "Test Site" }, @site.reload.read_attribute(:title).compact_blank)
  end

  test "a blank title in the default language is refused, even with a German one" do
    with_locales(%w[en de], default: "en")
    translate_site(title: "Danas Notizen")

    patch "/cs-studio/settings", params: { site_setting: { title: "" },
      base_updated_at: @site.reload.updated_at.iso8601(6) }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_select_in_stream "settings-title-errors", /can't be blank/
    assert_equal "Test Site", @site.reload.title(locale: "en")
  end

  test "an outdated German title shows the note, the confirm button and the switcher marker" do
    with_locales(%w[en de es], default: "en")
    translate_site(title: "Danas Notizen")
    Mobility.with_locale(:en) { @site.reload.update!(title: "Dana's Notes") }
    assert_equal :outdated, @site.reload.translation_state("title", "de")

    get "/cs-studio/settings", params: { locale: "de" }

    assert_response :success
    assert_select "#translation-note-site-setting-#{@site.id}-title", text: /Original changed since this was translated/
    assert_select "#translation-note-site-setting-#{@site.id}-title button[form='translation-confirm-form']", text: "Mark as up to date"
    assert_select "#language-switcher-outdated-de"
    assert_select "#language-switcher-outdated-es", count: 0
  end

  test "marking the German title up to date clears the note" do
    with_locales(%w[en de], default: "en")
    translate_site(title: "Danas Notizen")
    Mobility.with_locale(:en) { @site.reload.update!(title: "Dana's Notes") }

    post "/cs-studio/translations/confirm",
      params: { record_type: "SiteSetting", record_id: @site.id, field: "title", locale: "de" }, as: :turbo_stream

    assert_response :success
    assert_equal :current, @site.reload.translation_state("title", "de")
    assert Audit::Event.exists?(action: "settings.translation_confirmed")
  end

  test "marking a site field up to date needs settings.manage" do
    with_locales(%w[en de], default: "en")
    translate_site(title: "Danas Notizen")
    Mobility.with_locale(:en) { @site.reload.update!(title: "Dana's Notes") }
    sign_in_as(users(:author))

    post "/cs-studio/translations/confirm",
      params: { record_type: "SiteSetting", record_id: @site.id, field: "title", locale: "de" }, as: :turbo_stream

    assert_response :forbidden
    assert_equal :outdated, @site.reload.translation_state("title", "de")
  end

  test "confirming names the one settings row; any other id is not found" do
    with_locales(%w[en de], default: "en")

    post "/cs-studio/translations/confirm",
      params: { record_type: "SiteSetting", record_id: @site.id + 1, field: "title", locale: "de" }, as: :turbo_stream

    assert_response :not_found
  end

  # Review fix round 1: the form names the language it was rendered in,
  # even the default one -- otherwise the autosave right after switching the
  # default to German wrote the English title, still in the input, over the
  # German one.
  test "the default-language form always posts its own language" do
    get "/cs-studio/settings"

    assert_select "form[action='/cs-studio/settings?locale=en']"
  end

  test "changing the default language and then autosaving another field leaves the German title alone" do
    with_locales(%w[en de], default: "en")
    translate_site(title: "Danas Notizen")
    form_params = { title: "Test Site", tagline: "", time_zone: "UTC", trash_retention_days: 30 }
    get "/cs-studio/settings"
    form_url = css_select("##{Admin::SettingsFormComponent::DOM_ID} form").first["action"]

    patch form_url, params: { site_setting: form_params.merge(default_locale: "de"),
      base_updated_at: @site.reload.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success
    assert_equal "de", @site.reload.default_locale
    # The whole form comes back for the new default, still in English, now
    # with the German original beside it.
    assert_select_in_stream Admin::SettingsFormComponent::DOM_ID, /Danas Notizen/

    patch form_url, params: { site_setting: form_params.merge(default_locale: "de", trash_retention_days: 7),
      base_updated_at: @site.reload.updated_at.iso8601(6) }, as: :turbo_stream

    assert_response :success
    @site.reload
    assert_equal 7, @site.trash_retention_days
    assert_equal({ "en" => "Test Site", "de" => "Danas Notizen" }, @site.read_attribute(:title))
  end
end
