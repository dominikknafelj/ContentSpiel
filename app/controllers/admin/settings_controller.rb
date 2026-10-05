module Admin
  # The Settings module (cs-studio spec §6.1; round 3, Task 5): one screen of
  # cards -- Site, Languages, Publishing, AI translation -- and ONE form
  # (`#settings-form`) with ONE save footer. Settings no longer autosaves
  # (design pass spec §4, handoff B12): `PATCH /settings` is an ordinary form
  # submission, answered by a 303 to the same screen with the toast "Settings
  # saved" (decision D4), by the screen re-rendered at 422 with the error
  # summary when the service refuses, or at 409 when the form's base is stale.
  # It never answers a Turbo Stream.
  #
  # There's only ever one `SiteSetting` row (`SiteSetting#only_one_record_
  # exists`); every write goes through `Settings::Save`, which holds the
  # permission checks and the `settings.updated` event.
  #
  # WHO OPENS IT (decision D9): either `settings.manage` or `languages.manage`
  # (`MODULES`, and the gate below); each card and its nav link render only for
  # the right that owns them (`Admin::SettingsScreen::NavComponent`). Nothing
  # here is guarded per card by a `before_action`: the service enforces the
  # same split, and what the form carries is built from what the viewer may
  # manage, so a forged field outside their right reaches the service as a
  # refusal and comes back as the 403.
  class SettingsController < BaseController
    include FileParams
    include StaleForm

    # The stale banner (`admin/shared/_stale_banner`): the lead goes on to name who
    # changed it and when where the audit log says, and the message is the whole
    # banner where it doesn't.
    STALE_LEAD = "Settings were changed".freeze
    STALE_MESSAGE = "#{STALE_LEAD} elsewhere since you opened this screen. #{StaleForm::STALE_ADVICE}".freeze

    before_action -> { forbidden! unless holds_any?(%w[settings.manage languages.manage]) }
    # The AI test is a `settings.manage` action; the module gate above would
    # also let a languages-only viewer reach it.
    before_action -> { require_permission("settings.manage") }, only: :test_ai_connection

    def show
      @site_setting = Current.site
    end

    # What this form may carry, deliberately short: the default language is
    # NOT here (it is its own instant action behind a dialog,
    # `Locales::MakeDefault`; the service still accepts `default_locale` for
    # the setup wizard, so this list is what keeps a settings-only user from
    # changing it from here), and neither is `locales`. The language ORDER and
    # fallbacks are `languages` (rows of `code` and `fallback`; round 3, Task 6).
    # Every enabled language's title and tagline arrive together,
    # `translations[<code>][title|tagline]`.
    #
    # `Settings::Save` decides "this call has a site part" from what is PASSED,
    # so the arguments are built from what was POSTED (only the languages and
    # fields actually posted, never an empty hash), whoever the viewer is, and
    # the service decides: a field outside the viewer's right -- site fields
    # from a languages-only viewer, `languages` rows from a settings-only one --
    # is REFUSED (a 403 and one `access.denied`, nothing written), never
    # silently dropped. Neither viewer's own form carries such a field (the card
    # isn't rendered for them), so their Save stays a one-part call: a
    # languages-only viewer's form carries just the rows and a languages-only
    # call needs only `languages.manage` and leaves the site row alone.
    def update
      site = Current.site
      # A forged scalar (`site_setting=x`) is no form at all: read as an empty
      # one (nothing posted, nothing saved) rather than a 500 from `permit`.
      posted = params[:site_setting]
      posted = ActionController::Parameters.new unless posted.is_a?(ActionController::Parameters)
      permitted = posted.permit(
        :logo, :remove_logo, :time_zone, :trash_retention_days, :ai_provider, :ai_model, :language_order,
        translations: Locales.enabled.index_with { Settings::Save::TRANSLATED },
        social_links: [ :name, :url ],
        # `language_order` is the one tracked field that makes a reorder a
        # single change for the footer (`admin--sortable-rows`); the rows
        # themselves are what is read.
        languages: [ :code, :fallback ]
      )

      if stale_form?(site, params[:base_updated_at])
        @site_setting = site
        @submitted = permitted
        @tab_locale = admin_locale
        return render_stale(:show, site)
      end

      attributes, translated = site_arguments(permitted)
      result = Settings::Save.call(site, attributes: attributes, translations: translated, languages: language_arguments(site, permitted))

      if result.ok?
        redirect_to admin_settings_path(**admin_url_options), status: :see_other, notice: "Settings saved"
      else
        forbidden_or(result) do
          @site_setting = site
          @submitted = permitted
          @errors = site.errors.any? ? site.errors : result.errors
          @tab_locale = tab_for_errors(site.errors)
          render :show, status: :unprocessable_entity
        end
      end
    end

    # Test connection (translation helpers spec §6.2): one tiny request
    # with the *saved* provider, model and key (`AI.provider`, then the
    # provider's own `#test_connection`), reported inline under the button:
    # "CONNECTED · 412 MS" with the provider call's elapsed time, measured here
    # on the server, or the provider's own message. Neither carries the key.
    # Writes nothing, so it's not a service. (The key's save and remove are
    # `Admin::AiKeysController`.)
    def test_ai_connection
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      AI.provider.test_connection
      elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      render turbo_stream: ai_test_result_stream(milliseconds: elapsed)
    rescue AI::Error => error
      render turbo_stream: ai_test_result_stream(message: error.message), status: :unprocessable_entity
    end

    private

    # `[attributes, translations]` for `Settings::Save` from the permitted
    # params: the logo (a blank file input is dropped; the remove box detaches
    # unless a new file came with it), the social link rows in the order the
    # form numbered them, and only the languages/fields actually posted.
    def site_arguments(permitted)
      attributes = permitted.slice(:logo, :time_zone, :trash_retention_days, :ai_provider, :ai_model).to_h
      attributes = drop_blank_file_params(attributes, fields: %w[logo])
      attributes["logo"] = nil if !attributes.key?("logo") && ActiveModel::Type::Boolean.new.cast(permitted[:remove_logo])
      attributes["social_link_rows"] = social_link_rows(permitted[:social_links]) if rows_posted?(permitted[:social_links])

      translated = (permitted[:translations]&.to_h || {}).transform_values { |fields| fields.slice(*Settings::Save::TRANSLATED.map(&:to_s)) }.reject { |_, fields| fields.empty? }
      [ attributes, translated ]
    end

    # The complete ordered `[{ "code", "fallbacks" }]` for `Settings::Save`, or
    # nil when no rows were posted (the language part is then not in the call).
    # Rows arrive as `languages[][code]`/`languages[][fallback]` in row order.
    #
    # DECISION D7: the card's select stores ONE fallback, but a language may be
    # stored with several. A row's stored list is rewritten only when the
    # posted value differs from the stored FIRST entry -- the one the select
    # showed -- so an untouched row keeps all of its fallbacks, and a row whose
    # select was changed (to another language, or to "None") keeps only the
    # new choice. A row posting no `fallback` at all (the default's select is
    # disabled) is untouched too.
    def language_arguments(site, permitted)
      rows = permitted[:languages]
      return nil unless rows.is_a?(Array)

      rows = rows.grep(ActionController::Parameters).select { |row| row[:code].present? }
      return nil if rows.empty?

      rows.map do |row|
        code = row[:code].to_s
        stored = Array(site.locale_entry(code)&.dig("fallbacks")).map(&:to_s)
        changed = row.key?(:fallback) && row[:fallback].to_s != stored.first.to_s
        { "code" => code, "fallbacks" => changed ? [ row[:fallback].to_s ].reject(&:blank?) : stored }
      end
    end

    # `social_links[0][name]`-style rows arrive as a hash keyed by row number
    # (or, from a scripted client, a plain array); either way, row order.
    # Rows are an array, or a hash keyed by row number; any other shape (a forged
    # `social_links[name]=x`) is not rows at all, and leaves the stored links be.
    def rows_posted?(rows)
      rows.is_a?(Array) || (rows.respond_to?(:keys) && rows.keys.any? && rows.keys.all? { |key| key.to_s.match?(/\A\d+\z/) })
    end

    def social_link_rows(rows)
      rows = rows.respond_to?(:values) && !rows.is_a?(Array) ? rows.to_h.sort_by { |index, _| index.to_i }.map(&:last) : Array(rows)
      # Only rows that are hashes: a forged `social_links[name]=x` is a hash of
      # strings, not of rows.
      rows.grep(Hash).map { |row| row.to_h.symbolize_keys }
    end

    # The tab to show after a refusal: the language of the first error that
    # belongs to a translated field (the title rule is the default language's),
    # else the tab the editor was on (`locale`, kept current by `admin--settings-tabs`).
    def tab_for_errors(errors)
      errors.attribute_names.any? { |name| Settings::Save::TRANSLATED.include?(name) } ? Locales.default : admin_locale
    end

    def ai_test_result_stream(milliseconds: nil, message: nil)
      turbo_stream.replace(Admin::SettingsScreen::AiTestResultComponent::ID, Admin::SettingsScreen::AiTestResultComponent.new(milliseconds: milliseconds, message: message))
    end
  end
end
