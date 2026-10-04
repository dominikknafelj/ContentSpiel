require "test_helper"

# The Settings screen is one form with one save footer (round 3, Task 5,
# decisions D4/D6/D9): every enabled language's title and tagline are in the
# page at once, a save is an ordinary PATCH that redirects (303) with a toast,
# a refusal re-renders at 422 with the error summary, and a save on a stale
# base is refused at 409. Nothing here answers a Turbo Stream.
class Admin::SettingsTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
    @site = site_settings(:default)
  end

  def base = @site.reload.updated_at.iso8601(6)

  # What the form submits: only `site_setting` (plus the base), the way a
  # browser would -- the tests send just the fields they care about.
  def save(fields = {}, locale: nil, **more)
    params = { site_setting: fields.merge(more), base_updated_at: base }
    params[:locale] = locale if locale
    patch "/cs-studio/settings", params: params
  end

  def translations(**by_language) = { translations: by_language.transform_keys(&:to_s) }

  def translate_site(title:, tagline: nil, locale: "de")
    Mobility.with_locale(locale) { @site.update!(title: title, tagline: tagline) }
  end

  # -- the screen --------------------------------------------------------------

  test "every enabled language's title and tagline are in the page, with ids per language" do
    @site.update!(title: "Dana's Notes", tagline: "Things I learned")
    translate_site(title: "Danas Notizen")

    get "/cs-studio/settings"

    assert_response :success
    assert_select "form#settings-form"
    %w[en de es].each do |code|
      assert_select "input#settings-#{code}-title[name='site_setting[translations][#{code}][title]']"
      assert_select "input#settings-#{code}-tagline[name='site_setting[translations][#{code}][tagline]']"
    end
    assert_select "input#settings-en-title[value=?]", "Dana's Notes"
    assert_select "input#settings-de-title[value=?]", "Danas Notizen"
    assert_select "select[name='site_setting[default_locale]']", count: 0
    assert_select "h1", "Settings"
  end

  test "the Site card has a tab per language that only switches the visible pair" do
    get "/cs-studio/settings"

    assert_select "#settings-site-card nav.admin-language-tabs button[type=button][role=tab]", 3
    assert_select "#settings-site-card nav.admin-language-tabs button[role=tab][aria-selected='true']", text: "English"
    assert_select "#settings-site-card nav.admin-language-tabs a", count: 0
    assert_select "#settings-site-card [data-language-panel='en']:not([hidden])"
    assert_select "#settings-site-card [data-language-panel='de'][hidden]"
  end

  test "?locale picks the tab shown first" do
    get "/cs-studio/settings", params: { locale: "de" }

    assert_select "#settings-site-card nav.admin-language-tabs button[role=tab][aria-selected='true']", text: "Deutsch"
    assert_select "#settings-site-card [data-language-panel='de']:not([hidden])"
    assert_select "#settings-site-card [data-language-panel='en'][hidden]"
  end

  test "the default language shows no original; another language shows it beside its fields" do
    @site.update!(title: "Dana's Notes", tagline: "Things I learned")
    translate_site(title: "Danas Notizen")

    get "/cs-studio/settings"

    assert_select "[data-language-panel='en'] [data-original-for]", count: 0
    assert_select "[data-language-panel='de'] [data-original-for='title'] p", text: "Dana's Notes"
    assert_select "[data-language-panel='de'] [data-original-for='tagline'] p", text: "Things I learned"
    assert_select "[data-language-panel='de'] [data-translate-slot='title']"
  end

  test "the screen is a nav of anchors, one card per section, and one footer" do
    get "/cs-studio/settings"

    assert_select "nav[aria-label='Settings sections'] a", 4
    %w[site languages publishing ai].each do |id|
      assert_select "nav[aria-label='Settings sections'] a[href='##{id}']"
      assert_select "##{id}"
    end
    assert_select "nav[aria-label='Settings sections'] a[href='#languages']", text: "Languages"
    assert_select "nav[aria-label='Settings sections'] a[href='#ai']", text: "AI translation"
    assert_select ".admin-save-bar", 1
    assert_select "form#settings-form .admin-save-bar"
    assert_select "[data-controller~='admin--autosave']", count: 0
  end

  # -- saving -------------------------------------------------------------------

  test "saving two languages' titles at once writes both and records one settings.updated" do
    with_locales(%w[en de], default: "en")
    @site.reload

    assert_difference -> { Audit::Event.where(action: "settings.updated").count }, 1 do
      save translations(en: { title: "New Title", tagline: "New Tagline" }, de: { title: "Neuer Titel", tagline: "" })
    end

    assert_response :see_other
    assert_redirected_to "/cs-studio/settings"
    follow_redirect!
    assert_match(/Settings saved/, response.body)
    @site.reload
    assert_equal({ "en" => "New Title", "de" => "Neuer Titel" }, @site.read_attribute(:title).compact_blank)
    assert_equal "New Tagline", @site.tagline(locale: "en")
    event = Audit::Event.where(action: "settings.updated").order(:id).last
    assert_equal [ nil, "Neuer Titel" ], event.field_changes["de title"]
  end

  test "the redirect names the language when one is asked for" do
    with_locales(%w[en de], default: "en")

    save translations(en: { title: "Test Site" }), locale: "de"

    assert_redirected_to "/cs-studio/settings?locale=de"
  end

  test "a blank default-language title is refused with a summary linking its field, and the typed German is kept" do
    with_locales(%w[en de], default: "en")

    save translations(en: { title: "" }, de: { title: "Danas Notizen" })

    assert_response :unprocessable_entity
    assert_select ".admin-error-summary a[href='#settings-en-title']"
    assert_select "input#settings-de-title[value=?]", "Danas Notizen"
    assert_select "form#settings-form[data-admin--save-bar-dirty-value='true']"
    assert_not_equal "", @site.reload.title(locale: "en")
    assert_nil @site.read_attribute(:title)["de"]
  end

  test "a blank German title is fine: only the default language's title is required" do
    with_locales(%w[en de], default: "en")
    translate_site(title: "Danas Notizen")

    save translations(en: { title: "Test Site" }, de: { title: "" })

    assert_response :see_other
    assert_equal({ "en" => "Test Site" }, @site.reload.read_attribute(:title).compact_blank)
  end

  test "a language the site doesn't have is ignored, and an empty hash sends nothing to the service" do
    with_locales(%w[en de], default: "en")

    save translations(en: { title: "Kept" }, fr: { title: "Nope" })

    assert_response :see_other
    assert_nil @site.reload.read_attribute(:title)["fr"]
  end

  test "a forged default_locale changes nothing" do
    with_locales(%w[en de], default: "en")

    save({ default_locale: "de" }.merge(translations(en: { title: "Still English" })))

    assert_response :see_other
    assert_equal "en", @site.reload.default_locale
    assert_equal "Still English", @site.title(locale: "en")
  end

  test "uploading a logo attaches it, an empty file field keeps it, and the remove box detaches it" do
    save logo: fixture_file_upload("tiny.png", "image/png")
    assert_response :see_other
    assert @site.reload.logo.attached?

    # A browser submits an untouched file input as an empty part (Rack reads
    # it as ""): never "detach the logo".
    save translations(en: { title: "Still here" }).merge(logo: "")
    assert_response :see_other
    assert @site.reload.logo.attached?

    get "/cs-studio/settings"
    assert_select "input.cs-checkbox[type=checkbox][name='site_setting[remove_logo]']"
    assert_select "#settings-site-card img"

    save remove_logo: "1"
    assert_response :see_other
    assert_not @site.reload.logo.attached?

    get "/cs-studio/settings"
    assert_select "input[name='site_setting[remove_logo]']", count: 0
  end

  test "a newly chosen logo wins over the remove box in the same save" do
    @site.logo.attach(io: File.open(file_fixture("tiny.png")), filename: "tiny.png", content_type: "image/png")

    save logo: fixture_file_upload("tiny.png", "image/png"), remove_logo: "1"

    assert @site.reload.logo.attached?
  end

  # The links are stored as a `{ name => url }` jsonb hash, and jsonb does not
  # keep key order (shortest key first): what the form guarantees is the rows
  # it reads, not the order they come back in -- an existing limitation.
  test "social links drop half-filled and blank rows and are read by row number" do
    save social_links: {
      "0" => { name: "GitHub", url: "https://github.com/dana" },
      "1" => { name: "Mastodon", url: "" },
      "2" => { name: "", url: "https://example.org" },
      "3" => { name: "", url: "" },
      "4" => { name: "Blog", url: "https://example.org/blog" }
    }

    assert_response :see_other
    assert_equal({ "GitHub" => "https://github.com/dana", "Blog" => "https://example.org/blog" }, @site.reload.social_links)
    get "/cs-studio/settings"
    assert_select "#settings-social-links [data-admin--repeat-rows-target=list] input[name$='[name]']", 2
    assert_select "#settings-social-links input[value='GitHub']"
    assert_select "#settings-social-links input[value='https://example.org/blog']"
  end

  test "with no social links the form shows one empty row" do
    get "/cs-studio/settings"

    assert_select "input[name='site_setting[social_links][0][name]']", 1
    assert_select "#settings-social-links [data-admin--repeat-rows-target=list] input[name$='[name]']", 1
    assert_select "template#settings-social-link-template input[name$='[name]']", 1
    assert_select "button", text: "+ Add link"
  end

  test "a social link without a scheme is refused with a message, and the typed row stays" do
    save social_links: { "0" => { name: "GitHub", url: "github.com/dana" } }

    assert_response :unprocessable_entity
    assert_includes response.body, "must start with https://, http:// or mailto:"
    assert_select "input[name='site_setting[social_links][0][name]'][value='GitHub']"
    assert_equal({}, @site.reload.social_links.to_h)
  end

  test "the trash retention period is saved, and a negative one is refused" do
    get "/cs-studio/settings"
    assert_select "input[type='number'][name='site_setting[trash_retention_days]'][value=?]", "30"
    assert_select "[aria-labelledby=publishing]", /Keep trashed items for/
    assert_select "[aria-labelledby=publishing]", /Set to 0 to keep trashed items until someone empties the trash\./

    save trash_retention_days: 7
    assert_response :see_other
    assert_equal 7, @site.reload.trash_retention_days

    save trash_retention_days: -1
    assert_response :unprocessable_entity
    assert_select ".admin-error-summary a[href='#settings-trash_retention_days']", /must be greater than or equal to 0/
    assert_equal 7, @site.reload.trash_retention_days
  end

  test "the site time zone is saved, and an unknown one is refused" do
    get "/cs-studio/settings"
    assert_select "select[name='site_setting[time_zone]'] option[selected][value=?]", "UTC"
    assert_select "#settings-site-card", /Used for scheduled publishing\./

    save time_zone: "Berlin"
    assert_response :see_other
    assert_equal "Berlin", @site.reload.time_zone

    save time_zone: "Mars/Olympus"
    assert_response :unprocessable_entity
    assert_select ".admin-error-summary", /isn't a known time zone/
    assert_equal "Berlin", @site.reload.time_zone
  end

  # The form resends every field, so what the select shows as selected is
  # what a save writes back: a stored zone no option names used to fall to
  # the first option ("International Date Line West").
  test "a stored zone no option names stays selected, and a save that doesn't touch it keeps it" do
    @site.update_column(:time_zone, "America/Argentina/Cordoba")

    get "/cs-studio/settings"
    selected = css_select("select[name='site_setting[time_zone]'] option[selected]")
    assert_equal [ "America/Argentina/Cordoba" ], selected.map { |option| option["value"] }

    save translations(en: { title: "Retitled" }).merge(time_zone: selected.first["value"])

    assert_response :see_other
    assert_equal "Retitled", @site.reload.title
    assert_equal "America/Argentina/Cordoba", @site.time_zone
  end

  test "a stored IANA identifier shows as its Rails zone and saves as it" do
    @site.update_column(:time_zone, "Europe/Berlin")

    get "/cs-studio/settings"
    selected = css_select("select[name='site_setting[time_zone]'] option[selected]").map { |option| option["value"] }
    assert_equal 1, selected.size

    save time_zone: selected.first

    assert_response :see_other
    assert_equal "Europe/Berlin", @site.reload.effective_time_zone.tzinfo.name
  end

  # -- stale saves (D4) ---------------------------------------------------------

  test "a save on a stale base is refused with the banner, the typed values kept and nothing written" do
    stale = base
    save translations(en: { title: "First" })
    assert_response :see_other

    patch "/cs-studio/settings", params: { site_setting: translations(en: { title: "Second, from a stale tab" }).merge(trash_retention_days: 9), base_updated_at: stale }

    assert_response :conflict
    assert_includes response.body, "Settings were changed elsewhere since you opened this screen. Reload to see the latest — your changes are still in the form."
    assert_select "input#settings-en-title[value=?]", "Second, from a stale tab"
    assert_select "input[name='site_setting[trash_retention_days]'][value='9']"
    assert_select "input[name=base_updated_at][value=?]", stale
    assert_equal "First", @site.reload.title
    assert_equal 30, @site.trash_retention_days
  end

  test "a blank or unparseable base is not stale" do
    patch "/cs-studio/settings", params: { site_setting: translations(en: { title: "No base" }) }
    assert_response :see_other
    patch "/cs-studio/settings", params: { site_setting: translations(en: { title: "Junk base" }), base_updated_at: "yesterday" }
    assert_response :see_other
    assert_equal "Junk base", @site.reload.title
  end

  # -- who sees what (D9) -------------------------------------------------------

  def user_holding(*keys)
    user = users(:editor_branch)
    keys.each { |key| AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: key, scope: {}) }
    AccessControl::Membership.create!(user: user, group: access_control_groups(:branch_editors)) unless user.groups.exists?(access_control_groups(:branch_editors).id)
    user
  end

  test "a settings.manage-only user sees the Site, Publishing and AI cards and no Languages" do
    sign_in_as(user_holding("settings.manage"))

    get "/cs-studio/settings"

    assert_response :success
    assert_select "nav[aria-label='Settings sections'] a", 3
    assert_select "nav[aria-label='Settings sections'] a[href='#languages']", count: 0
    assert_select "#languages", count: 0
    %w[site publishing ai].each { |id| assert_select "##{id}" }
    assert_select "form#settings-form"
  end

  test "a languages.manage-only user gets the screen with the Languages link and card and no form" do
    sign_in_as(user_holding("languages.manage"))

    get "/cs-studio/settings"

    assert_response :success
    assert_select "nav[aria-label='Settings sections'] a", 1
    assert_select "nav[aria-label='Settings sections'] a[href='#languages']", text: "Languages"
    assert_select "section[aria-labelledby=languages] a[href='/cs-studio/settings/languages']", text: "Open languages"
    assert_select "#settings-site-card", count: 0
    assert_select "form#settings-form", count: 0
    assert_select ".admin-save-bar", count: 0
    assert_select "nav[aria-label='Modules'] a", text: "Settings"
  end

  test "a user with neither right gets the 403 page" do
    sign_in_as(users(:author))

    get "/cs-studio/settings"

    assert_response :forbidden
    assert_select "nav[aria-label='Modules']"
  end

  test "a forged field from a languages.manage-only user is refused by the service and shown as the 403" do
    sign_in_as(user_holding("languages.manage"))

    assert_difference -> { Audit::Event.where(action: "access.denied").count }, 1 do
      patch "/cs-studio/settings", params: { site_setting: translations(en: { title: "Forged" }).merge(trash_retention_days: 1), base_updated_at: base }
    end

    assert_response :forbidden
    assert_equal "Test Site", @site.reload.title
    assert_equal 30, @site.trash_retention_days
  end

  # -- translations of the site text ---------------------------------------------

  test "an outdated German title shows the note, the confirm button and the tab marker" do
    with_locales(%w[en de es], default: "en")
    translate_site(title: "Danas Notizen")
    Mobility.with_locale(:en) { @site.reload.update!(title: "Dana's Notes") }
    assert_equal :outdated, @site.reload.translation_state("title", "de")

    get "/cs-studio/settings"

    assert_response :success
    card = "#reference-card-site-setting-#{@site.id}-title-de"
    assert_select "#{card}[data-translation-state='outdated']"
    assert_select "#{card} button[form='translation-confirm-form']", text: "Still correct — mark up to date"
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
    assert_includes response.body, %(target="reference-card-site-setting-#{@site.id}-title-de")
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
end
