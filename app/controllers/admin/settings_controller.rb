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

    ID_PREFIX = "settings"

    STALE_MESSAGE = "Settings were changed elsewhere since you opened this screen. Reload to see the latest — your changes are still in the form.".freeze

    before_action -> { forbidden! unless holds_any?(%w[settings.manage languages.manage]) }
    # The AI test and the key are `settings.manage` actions; the module gate
    # above would also let a languages-only viewer reach them.
    before_action -> { require_permission("settings.manage") }, only: %i[test_ai_connection ai_key]

    def show
      @site_setting = Current.site
    end

    # What this form may carry, deliberately short: the default language is
    # NOT here (it becomes its own instant action behind a dialog,
    # `Locales::MakeDefault`; the service still accepts `default_locale` for
    # the setup wizard, so this list is what keeps a settings-only user from
    # changing it from here), and neither are `locales`/`languages` (round 3,
    # Task 6). Every enabled language's title and tagline arrive together,
    # `translations[<code>][title|tagline]`.
    #
    # `Settings::Save` decides "this call has a site part" from what is PASSED,
    # so the arguments are built from what the viewer may manage: a
    # `settings.manage` holder's attributes and per-language texts (only the
    # languages and fields actually posted, never an empty hash); a viewer
    # without it passes neither, and the service answers with the refusal.
    def update
      site = Current.site
      permitted = params.fetch(:site_setting, ActionController::Parameters.new).permit(
        :logo, :remove_logo, :time_zone, :trash_retention_days, :ai_provider, :ai_model,
        translations: Locales.enabled.index_with { Settings::Save::TRANSLATED },
        social_links: [ :name, :url ]
      )

      if stale?(site, params[:base_updated_at])
        @site_setting = site
        @submitted = permitted
        @stale = true
        return render(:show, status: :conflict)
      end

      attributes, translated = can?("settings.manage") ? site_arguments(permitted) : [ {}, {} ]
      result = Settings::Save.call(site, attributes: attributes, translations: translated)

      if result.ok?
        redirect_to admin_settings_path(**admin_url_options), status: :see_other, notice: "Settings saved"
      else
        forbidden_or(result) do
          @site_setting = site
          @submitted = permitted
          @errors = site.errors.any? ? site.errors : result.errors
          render :show, status: :unprocessable_entity
        end
      end
    end

    # Test connection (translation helpers spec §6.2): one tiny request
    # with the *saved* provider, model and key (`AI.provider`, then the
    # provider's own `#test_connection`), reported inline under the button.
    # Writes nothing, so it's not a service.
    def test_ai_connection
      AI.provider.test_connection
      render turbo_stream: ai_test_result_stream(message: "Connection OK.", ok: true)
    rescue AI::Error => error
      render turbo_stream: ai_test_result_stream(message: error.message, ok: false), status: :unprocessable_entity
    end

    # Save key / Remove key (translation helpers spec §6.2): an instant action
    # of its own, because the key is deliberately not part of the Settings
    # form (it is never rendered, so it can't be a pending change). A blank
    # `ai_api_key` keeps the stored key, `remove_ai_key` clears it unless a new
    # one was typed in the same submit. Answers with the key section (and the
    # forms that sit beside it) replaced, and the main form's base moved on --
    # the key write touches `updated_at`, and a base left behind would make
    # the next Save look stale. Round 3's Task 7 rebuilds this card.
    def ai_key
      site = Current.site
      attributes = {}
      key = params.dig(:site_setting, :ai_api_key).to_s
      attributes["ai_api_key"] = key if key.present?
      attributes["ai_api_key"] = nil if ActiveModel::Type::Boolean.new.cast(params.dig(:site_setting, :remove_ai_key)) && key.blank?

      result = attributes.any? ? Settings::Save.call(site, attributes: attributes) : nil
      streams = [
        turbo_stream.replace("#{ID_PREFIX}-ai-key-section", partial: "admin/settings/ai_key_field", locals: { site_setting: site }),
        turbo_stream.replace("#{ID_PREFIX}-ai-key-forms", partial: "admin/settings/ai_key_forms", locals: { site_setting: site }),
        turbo_stream.replace("#{ID_PREFIX}-base-updated-at", partial: "admin/shared/base_updated_at_field",
          locals: { id: "#{ID_PREFIX}-base-updated-at", value: site.reload.updated_at.iso8601(6), name: "base_updated_at", form: "#{ID_PREFIX}-form" })
      ]
      streams << turbo_stream.append("toasts", Admin::ToastComponent.new(message: result.errors.to_sentence, kind: :error)) if result && !result.ok?

      render turbo_stream: streams, status: (result && !result.ok? ? (result.denied? ? :forbidden : :unprocessable_entity) : :ok)
    end

    private

    # The form's own comparison, a few lines the same shape as the editors'
    # (`AutosaveResponses#stale_base?`, which is private to autosave): the
    # row as just loaded is newer than the base the form carried. Blank or
    # unparseable is not stale -- non-JS and scripted clients never send one.
    def stale?(site, base)
      return false if base.blank?

      Time.iso8601(base) < site.updated_at
    rescue ArgumentError
      false
    end

    # `[attributes, translations]` for `Settings::Save` from the permitted
    # params: the logo (a blank file input is dropped; the remove box detaches
    # unless a new file came with it), the social link rows in the order the
    # form numbered them, and only the languages/fields actually posted.
    def site_arguments(permitted)
      attributes = permitted.slice(:logo, :time_zone, :trash_retention_days, :ai_provider, :ai_model).to_h
      attributes = drop_blank_file_params(attributes, fields: %w[logo])
      attributes["logo"] = nil if !attributes.key?("logo") && ActiveModel::Type::Boolean.new.cast(permitted[:remove_logo])
      attributes["social_link_rows"] = social_link_rows(permitted[:social_links]) if permitted.key?(:social_links)

      translated = (permitted[:translations]&.to_h || {}).transform_values { |fields| fields.slice(*Settings::Save::TRANSLATED.map(&:to_s)) }.reject { |_, fields| fields.empty? }
      [ attributes, translated ]
    end

    # `social_links[0][name]`-style rows arrive as a hash keyed by row number
    # (or, from a scripted client, a plain array); either way, row order.
    def social_link_rows(rows)
      rows = rows.respond_to?(:values) && !rows.is_a?(Array) ? rows.to_h.sort_by { |index, _| index.to_i }.map(&:last) : Array(rows)
      rows.map { |row| row.to_h.symbolize_keys }
    end

    def ai_test_result_stream(message:, ok:)
      turbo_stream.replace("#{ID_PREFIX}-ai-test-result", partial: "admin/settings/ai_test_result", locals: { message: message, ok: ok })
    end
  end
end
