require "test_helper"

# The Languages card inside Settings (round 3, Task 6; decisions D5, D7, D8,
# D9, D10) -- deliberately not named `languages_test.rb`:
# `test/integration/admin/languages_test.rb` is the page editor's own language
# switcher. What the card keeps from the old Languages screen: Add language,
# Turn off and the order/fallbacks, the last now fields of the Settings form
# (`PATCH /settings`, `Settings::Save`'s `languages:`). New: the default
# language as an instant action (`PATCH /settings/languages/:code/default`).
class Admin::LanguageSettingsTest < ActionDispatch::IntegrationTest
  setup do
    @site = site_settings(:default)
    @site.update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
  end

  def base = @site.reload.updated_at.iso8601(6)

  # What the form submits for the language rows (a hash per row, in row order).
  def save_languages(rows, **more)
    patch "/cs-studio/settings", params: { site_setting: { languages: rows }.merge(more), base_updated_at: base }
  end

  def user_holding(*keys)
    user = users(:editor_branch)
    keys.each { |key| AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: key, scope: {}) }
    AccessControl::Membership.create!(user: user, group: access_control_groups(:branch_editors)) unless user.groups.exists?(access_control_groups(:branch_editors).id)
    user
  end

  # -- the card ------------------------------------------------------------------

  test "the card has a row per enabled language with its controls, and the order as one tracked field" do
    @site.update!(locales: [ { "code" => "en" }, { "code" => "de", "fallbacks" => [ "en" ] }, { "code" => "es" } ])

    get "/cs-studio/settings"

    assert_response :success
    assert_select "form#settings-form section[aria-labelledby=languages]"
    assert_select "#language-en", text: /English\s*\//
    assert_select "#language-de", text: %r{Deutsch\s*/de}
    assert_select "#settings-language-order[name='site_setting[language_order]'][value='en,de,es'][data-save-bar-track]"
    assert_select "#language-de input[type=hidden][name='site_setting[languages][][code]'][value='de']"
    assert_select "#language-de select[name='site_setting[languages][][fallback]'] option[selected][value='en']"
    assert_select "#language-de select option", 3 # None (default), English, Español
    assert_select "#language-de select option[value='']", text: "None (default)"
    assert_select "#language-de select option[value='de']", count: 0

    # The default's select is disabled and reads "None (default)"; it can't be turned off.
    assert_select "#language-en select[disabled] option[selected][value='']", text: "None (default)"
    # The default's row has only the inert spacer copy of the button (it keeps the columns in line).
    assert_select "#language-en button:not([disabled])", text: "Turn off…", count: 0
    assert_select "#language-en button[data-admin--dialog-id-param^='language-off-dialog']", count: 0
    assert_select "#language-de button[data-admin--dialog-id-param='language-off-dialog-de']", text: "Turn off…"
  end

  test "the default is a tag and buttons, never a field of the Settings form, and the instant actions sit outside it" do
    get "/cs-studio/settings"

    # No radio group (final wave B, C-M9): a tag on the default row, a dialog
    # trigger with no name on the others -- nothing the form could submit.
    assert_select "#settings-languages-card input[type=radio]", count: 0
    assert_select "#language-en [data-default-tag]", text: "Default"
    assert_select "#settings-languages-card button[type=button]:not([name])", text: "Make default", count: 2
    assert_select "#language-de button[data-admin--dialog-id-param='language-default-dialog-de'][aria-label='Make Deutsch the default language']"
    assert_select "form#settings-form form", count: 0
    assert_select "form#language-default-form", count: 0
    assert_select "form#language-add-form[action='/cs-studio/settings/languages'][method=post]"
    assert_select "#language-add-code[form='language-add-form'] option[value='fr']"
    assert_select "#language-add-code option[value='de']", count: 0
    # Dialogs live outside the form, one pair per non-default language.
    assert_select "form#settings-form dialog", count: 0
    assert_select "dialog#language-default-dialog-de"
    assert_select "dialog#language-off-dialog-es"
    assert_select "dialog#language-default-dialog-en", count: 0
  end

  test "Default, Turn off and Add carry the pending-lock controls and its hint" do
    get "/cs-studio/settings"

    assert_select "#settings-languages-card[data-controller~='admin--pending-lock']"
    assert_select "#settings-languages-card [data-admin--pending-lock-target=hint]"
    assert_select "#settings-languages-card button[data-admin--pending-lock-target=control]", text: "Make default", count: 2
    assert_select "#settings-languages-card button[data-admin--pending-lock-target=control]", text: "Turn off…", count: 2
    assert_select "#settings-languages-card #language-add-code[data-admin--pending-lock-target=control]"
    assert_select "#settings-languages-card button[type=submit][form='language-add-form'][data-admin--pending-lock-target=control]", text: "Add language"
  end

  test "the Turn off dialog is neutral, and the default dialog names the move and the item count" do
    Mobility.with_locale(:de) { @site.update!(title: "Danas Notizen") }
    @site.reload
    create_page(title: "About")

    get "/cs-studio/settings"

    assert_select "dialog#language-off-dialog-de h2, dialog#language-off-dialog-de [id$=title]", text: "Turn off Deutsch?"
    assert_select "dialog#language-off-dialog-de", text: /Deutsch disappears from the language switcher and \/de pages show “not found”\. Translations are kept, so turning it back on restores them\./
    assert_select "dialog#language-off-dialog-de form[action='/cs-studio/settings/languages/de'] input[name=_method][value=delete]"
    assert_select "dialog#language-off-dialog-de button.bg-danger, dialog#language-off-dialog-de [class*='danger']", count: 0
    assert_select "dialog#language-off-dialog-de button[type=submit]", text: "Turn off Deutsch"

    assert_select "dialog#language-default-dialog-de", text: %r{Make Deutsch the default\?}
    assert_select "dialog#language-default-dialog-de", text: %r{Deutsch moves to / and English to /en\. Existing links to English pages without /en will open the Deutsch version, or show “not found” where there is none\.}
    expected = Translations::StateIndex.translated_record_count
    assert_operator expected, :>=, 1
    assert_select "dialog#language-default-dialog-de", text: /Deutsch becomes the source language, so every translation is marked outdated \(#{expected} items?\)\./
    assert_select "dialog#language-default-dialog-de form[action='/cs-studio/settings/languages/de/default'] input[name=_method][value=patch]"
    assert_select "dialog#language-default-dialog-de button[type=submit]", text: "Change default language"
  end

  # Final fix wave (S-M4): the "(N items)" count is a scan of every page, post
  # and image, so it runs only for a render that shows it -- a `languages.manage`
  # holder's, with a language to make the default -- and once, however many
  # dialogs there are. (Not cached: the only key that moves with every stored
  # translation is `PublicSite.content_version`, which is fifteen aggregate
  # scans of its own, more than the one query it would save.)
  test "the item count is queried once when a default dialog renders, and not at all otherwise" do
    counts = lambda do |&request|
      seen = 0
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        seen += 1 if payload[:sql].include?("jsonb_path_exists") && payload[:name] != "SCHEMA"
      end
      ActiveRecord::Base.uncached(&request)
      seen
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    @site.update!(locales: [ { "code" => "en" }, { "code" => "de" }, { "code" => "es" } ])
    assert_equal 1, counts.call { get "/cs-studio/settings" }
    assert_select "dialog[id^='language-default-dialog-']", 2

    @site.update!(locales: [ { "code" => "en" } ])
    assert_equal 0, counts.call { get "/cs-studio/settings" }

    @site.update!(locales: [ { "code" => "en" }, { "code" => "de" } ])
    sign_in_as(user_holding("settings.manage"))
    assert_equal 0, counts.call { get "/cs-studio/settings" }
    assert_response :success
  end

  test "the old Languages screen redirects permanently to the card, keeping the query" do
    get "/cs-studio/settings/languages"
    assert_response :moved_permanently
    assert_redirected_to "/cs-studio/settings#languages"

    get "/cs-studio/settings/languages?locale=de"
    assert_redirected_to "/cs-studio/settings?locale=de#languages"
  end

  # Final fix wave (Task 6 M1): `delete_suffix("/languages")` left a trailing
  # slash or a format in place, so the 301 pointed at the URL it came from.
  test "the old Languages screen's redirect also strips a trailing slash or a format, so it can't loop" do
    get "/cs-studio/settings/languages/"
    assert_response :moved_permanently
    assert_redirected_to "/cs-studio/settings#languages"

    get "/cs-studio/settings/languages.html?locale=de"
    assert_response :moved_permanently
    assert_redirected_to "/cs-studio/settings?locale=de#languages"
  end

  # -- saving the order and fallbacks with the footer --------------------------------

  test "one Save writes a new order and a fallback through Settings::Save, with its events" do
    @site.update!(locales: [ { "code" => "en" }, { "code" => "de" }, { "code" => "es" } ])

    assert_difference -> { Audit::Event.where(action: "language.configured").count }, 1 do
      save_languages(
        [ { code: "es" }, { code: "en" }, { code: "de", fallback: "en" } ],
        translations: { "en" => { title: "Renamed" } }
      )
    end

    assert_response :see_other
    assert_redirected_to "/cs-studio/settings"
    @site.reload
    assert_equal %w[es en de], @site.locale_codes
    assert_equal [ "en" ], @site.locale_entry("de")["fallbacks"]
    assert_equal "Renamed", @site.title(locale: "en")
    assert_equal 1, Audit::Event.where(action: "settings.updated").where("occurred_at >= ?", 1.minute.ago).count
  end

  test "an untouched row keeps its stored list of several fallbacks; a changed one keeps only the new choice (D7)" do
    @site.update!(locales: [ { "code" => "en" }, { "code" => "de", "fallbacks" => %w[es en] }, { "code" => "es", "fallbacks" => %w[de en] } ])

    get "/cs-studio/settings"
    assert_select "#language-de select option[selected][value='es']"

    # The form posts what its selects show: de's first entry (untouched), es changed to "None".
    save_languages([ { code: "en" }, { code: "de", fallback: "es" }, { code: "es", fallback: "" } ])
    assert_response :see_other

    @site.reload
    assert_equal %w[es en], @site.locale_entry("de")["fallbacks"]
    assert_nil @site.locale_entry("es")["fallbacks"]
  end

  test "changing a multi-fallback row to another language keeps only that one" do
    @site.update!(locales: [ { "code" => "en" }, { "code" => "de", "fallbacks" => %w[es en] }, { "code" => "es" } ])

    save_languages([ { code: "en" }, { code: "de", fallback: "en" }, { code: "es" } ])

    assert_equal [ "en" ], @site.reload.locale_entry("de")["fallbacks"]
  end

  # D7, case (b): moving rows changes nothing about a row whose select wasn't
  # touched -- the posted value is still the stored FIRST entry.
  test "an order-only change keeps a multi-fallback row's whole list (D7)" do
    @site.update!(locales: [ { "code" => "en" }, { "code" => "de", "fallbacks" => %w[es en] }, { "code" => "es" } ])

    save_languages([ { code: "es", fallback: "" }, { code: "de", fallback: "es" }, { code: "en" } ])

    assert_response :see_other
    @site.reload
    assert_equal %w[es de en], @site.locale_codes
    assert_equal %w[es en], @site.locale_entry("de")["fallbacks"]
  end

  test "a forged order with an omitted, duplicate or unknown code is a 422 with the message, and nothing is written" do
    @site.update!(locales: [ { "code" => "en" }, { "code" => "de" }, { "code" => "es" } ])
    before = @site.reload.locales

    [
      [ { code: "de" }, { code: "en" } ],
      [ { code: "de" }, { code: "en" }, { code: "es" }, { code: "de" } ],
      [ { code: "de" }, { code: "en" }, { code: "es" }, { code: "fr" } ],
      [ { code: "de" }, { code: "en" }, { code: "xx" } ]
    ].each do |rows|
      assert_no_difference -> { Audit::Event.where(action: %w[language.configured settings.updated]).count } do
        save_languages(rows, trash_retention_days: 3)
      end

      assert_response :unprocessable_entity, rows.inspect
      assert_select ".admin-error-summary[role=alert]", text: /must list exactly the enabled languages/
      assert_equal before, @site.reload.locales
      assert_equal 30, @site.trash_retention_days
    end
  end

  # Final fix wave (S-M2): the site part is saved first and the language part
  # then refuses, so the transaction rolls back -- but `Current.site`, the one
  # object the re-render reads, still held the rolled-back values as if they
  # were stored. What was typed comes back from the params; everything read
  # from the record must be the stored row.
  test "a save whose language part is refused re-renders the stored site: the original beside the German fields is not the rolled-back title" do
    @site.update!(locales: [ { "code" => "en" }, { "code" => "de" } ])
    Mobility.with_locale(:en) { @site.update!(title: "Stored title") }

    save_languages([ { code: "de" }, { code: "en", fallback: "fr" } ], translations: { "en" => { title: "Typed title" } })

    assert_response :unprocessable_entity
    assert_select "#settings-en-title[value='Typed title']"
    assert_select "[data-language-panel='de'] [data-original-for='title'] p", text: "Stored title"
    assert_equal "Stored title", @site.reload.title(locale: "en")
  end

  test "the default's row posts no fallback and keeps whatever it had" do
    @site.update!(locales: [ { "code" => "en", "fallbacks" => [ "de" ] }, { "code" => "de" } ])

    save_languages([ { code: "en" }, { code: "de", fallback: "en" } ])

    assert_equal [ "de" ], @site.reload.locale_entry("en")["fallbacks"]
    assert_equal [ "en" ], @site.locale_entry("de")["fallbacks"]
  end

  test "a refused list (a fallback that is not enabled) comes back at 422 with what was typed, and writes nothing" do
    @site.update!(locales: [ { "code" => "en" }, { "code" => "de" } ])

    save_languages([ { code: "de" }, { code: "en", fallback: "fr" } ])

    assert_response :unprocessable_entity
    assert_select ".admin-error-summary[role=alert]", text: /isn't enabled|isn’t enabled/
    assert_select "form#settings-form[data-admin--save-bar-dirty-value='true']"
    # The order as typed, not the stored one.
    assert_select "#settings-language-order[value='de,en']"
    assert_equal %w[en de], @site.reload.locale_codes
  end

  test "malformed rows are not an error page: junk is no rows, a row without a code is ignored" do
    @site.update!(locales: [ { "code" => "en" }, { "code" => "de" } ])

    patch "/cs-studio/settings", params: { site_setting: { languages: "junk", trash_retention_days: 7 }, base_updated_at: base }
    assert_response :see_other
    assert_equal %w[en de], @site.reload.locale_codes

    save_languages([ { fallback: "en" }, { code: "de" }, { code: "en" } ])
    assert_response :see_other
    assert_equal %w[de en], @site.reload.locale_codes

    # A fallback that is no scalar (a list, a hash) is no choice at all: the row
    # is read as untouched, its stored fallbacks kept, and nothing raises.
    @site.update!(locales: [ { "code" => "en" }, { "code" => "de", "fallbacks" => [ "en" ] } ])
    save_languages([ { code: "en", fallback: { "x" => "de" } }, { code: "de", fallback: [ "", "junk" ] } ])
    assert_response :see_other
    assert_equal %w[en de], @site.reload.locale_codes
    assert_equal [ "en" ], @site.locale_entry("de")["fallbacks"]
    assert_empty Array(@site.locale_entry("en")["fallbacks"])
  end

  test "a languages.manage-only viewer's Save (rows and the base, no site field) is a languages-only call that leaves the site row alone" do
    @site.update!(locales: [ { "code" => "en" }, { "code" => "de" } ])
    sign_in_as(user_holding("languages.manage"))

    get "/cs-studio/settings"
    # Their form carries the rows and the order, and nothing of the site's.
    assert_select "form#settings-form input[name^='site_setting[']:not([name^='site_setting[language'])", count: 0

    assert_no_difference -> { Audit::Event.where(action: "settings.updated").count } do
      save_languages([ { code: "de" }, { code: "en" } ])
    end

    assert_response :see_other
    assert_equal %w[de en], @site.reload.locale_codes
    assert_equal 30, @site.trash_retention_days
  end

  test "a site field forged by a languages.manage-only viewer is refused with the rows: 403, one denial, nothing written" do
    @site.update!(locales: [ { "code" => "en" }, { "code" => "de" } ])
    sign_in_as(user_holding("languages.manage"))

    assert_difference -> { Audit::Event.where(action: "access.denied").count }, 1 do
      save_languages([ { code: "de" }, { code: "en" } ], trash_retention_days: 1)
    end

    assert_response :forbidden
    assert_equal %w[en de], @site.reload.locale_codes
    assert_equal 30, @site.trash_retention_days
  end

  test "a languages-only Save on a stale base is a 409 and writes nothing" do
    @site.update!(locales: [ { "code" => "en" }, { "code" => "de" } ])
    sign_in_as(user_holding("languages.manage"))
    stale = base
    @site.touch

    patch "/cs-studio/settings", params: { site_setting: { languages: [ { code: "de" }, { code: "en" } ] }, base_updated_at: stale }

    assert_response :conflict
    assert_equal %w[en de], @site.reload.locale_codes
  end

  test "a settings.manage-only viewer can't post languages: refused as the 403, nothing changes" do
    @site.update!(locales: [ { "code" => "en" }, { "code" => "de" } ])
    sign_in_as(user_holding("settings.manage"))

    assert_difference -> { Audit::Event.where(action: "access.denied").count }, 1 do
      save_languages([ { code: "de" }, { code: "en" } ])
    end

    assert_response :forbidden
    assert_equal %w[en de], @site.reload.locale_codes
  end

  test "a settings.manage-only viewer sees no Languages card and the rest of the form saves as before" do
    sign_in_as(user_holding("settings.manage"))

    get "/cs-studio/settings"
    assert_select "section[aria-labelledby=languages]", count: 0
    assert_select "#settings-language-order", count: 0
    assert_select "form#language-add-form", count: 0
  end

  # -- Add, Turn off, Default: instant actions -----------------------------------------

  test "add language enables a supported language and answers 303 to the card with a toast" do
    post "/cs-studio/settings/languages", params: { code: "fr" }

    assert_response :see_other
    assert_redirected_to "/cs-studio/settings#languages"
    follow_redirect!
    assert_includes response.body, "Français added"
    assert_includes @site.reload.locale_codes, "fr"
  end

  test "turn off disables a non-default language and toasts" do
    @site.update!(locales: [ { "code" => "en" }, { "code" => "de" } ])

    delete "/cs-studio/settings/languages/de"

    assert_response :see_other
    assert_redirected_to "/cs-studio/settings#languages"
    follow_redirect!
    assert_includes response.body, "Deutsch turned off"
    assert_not_includes @site.reload.locale_codes, "de"
  end

  test "turning off the default is refused by the service and says why" do
    delete "/cs-studio/settings/languages/en"

    assert_response :see_other
    follow_redirect!
    assert_includes response.body, "default language can&#39;t be disabled"
    assert_includes @site.reload.locale_codes, "en"
  end

  test "make default moves it, carries the title over, rebuilds the states and toasts" do
    @site.update!(locales: [ { "code" => "en" }, { "code" => "de" } ])
    Mobility.with_locale(:en) { @site.update!(title: "Dana's Notes") }

    assert_difference -> { Audit::Event.where(action: "language.default_changed").count }, 1 do
      patch "/cs-studio/settings/languages/de/default"
    end

    assert_response :see_other
    assert_redirected_to "/cs-studio/settings#languages"
    follow_redirect!
    assert_includes response.body, "Deutsch is now the default language"
    @site.reload
    assert_equal "de", @site.default_locale.to_s
    assert_equal "Dana's Notes", @site.title(locale: "de")
  end

  # Final fix wave (Task 6 M6): the services answer a request for what is
  # already true as a no-op success. The toast must not then claim a change.
  test "a forged add, turn off or default that changes nothing toasts nothing" do
    @site.update!(locales: [ { "code" => "en" }, { "code" => "de" } ])

    post "/cs-studio/settings/languages", params: { code: "de" }
    assert_redirected_to "/cs-studio/settings#languages"
    follow_redirect!
    assert_not response.body.include?("Deutsch added"), "a toast claims a change"
    assert_select "#toasts [role=status], #toasts [role=alert]", count: 0

    delete "/cs-studio/settings/languages/fr"
    assert_redirected_to "/cs-studio/settings#languages"
    follow_redirect!
    assert_not response.body.include?("turned off"), "a toast claims a change"
    assert_select "#toasts [role=status], #toasts [role=alert]", count: 0

    patch "/cs-studio/settings/languages/en/default"
    assert_redirected_to "/cs-studio/settings#languages"
    follow_redirect!
    assert_not response.body.include?("is now the default language"), "a toast claims a change"
    assert_select "#toasts [role=status], #toasts [role=alert]", count: 0
    assert_equal %w[en de], @site.reload.locale_codes
  end

  test "make default for a language that isn't enabled is 422 and changes nothing" do
    patch "/cs-studio/settings/languages/fr/default"

    assert_response :unprocessable_entity
    assert_equal "en", @site.reload.default_locale.to_s
  end

  test "make default needs languages.manage: a settings.manage-only viewer gets the 403" do
    @site.update!(locales: [ { "code" => "en" }, { "code" => "de" } ])
    sign_in_as(user_holding("settings.manage"))

    patch "/cs-studio/settings/languages/de/default"

    assert_response :forbidden
    assert_equal "en", @site.reload.default_locale.to_s
  end

  test "Add and Turn off need languages.manage too" do
    @site.update!(locales: [ { "code" => "en" }, { "code" => "de" } ])
    sign_in_as(user_holding("settings.manage"))

    post "/cs-studio/settings/languages", params: { code: "fr" }
    assert_response :forbidden
    delete "/cs-studio/settings/languages/de"
    assert_response :forbidden
    assert_equal %w[en de], @site.reload.locale_codes
  end
end
