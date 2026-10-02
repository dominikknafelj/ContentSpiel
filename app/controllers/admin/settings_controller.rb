module Admin
  # The Settings module (cs-studio spec §6.1, Task 8): title, tagline, logo
  # (the explicit-remove pattern, mirroring `Admin::PagesController`'s own
  # hero image), social link rows (`SiteSetting#social_link_rows=`) and the
  # default language (restricted to the site's own enabled languages, the
  # same set `Admin::PageSettingsFormComponent`-style forms elsewhere never
  # need to restrict since they read `Locales.enabled` directly, but this
  # screen is the one place that value is itself being *set*).
  #
  # There's only ever one `SiteSetting` row (`SiteSetting#only_one_record_
  # exists`); it's written through `Settings::Save`, like the setup
  # wizard's site step -- which is where the permission check and the
  # `settings.updated` event live (access-control design spec §3.4).
  class SettingsController < BaseController
    include AutosaveResponses
    include FileParams

    ID_PREFIX = "settings"

    # The module is `settings.manage` (access-control design spec §3.4);
    # `Settings::Save` checks it again for every write.
    before_action -> { require_permission("settings.manage") }

    def show
      @site_setting = Current.site
    end

    # The settings form's own autosave endpoint (spec §6.1), same shape as
    # `Admin::PagesController#update`: every field in `params[:site_setting]`
    # PATCHes here together, answered with the shared Turbo Stream response
    # regardless of success.
    #
    # The title and tagline (`Settings::Save::TRANSLATED`) are saved in the
    # language being edited (`admin_locale`, the `?locale=` the form posts
    # to), the same way `Admin::PagesController#update` saves a page title;
    # every other field is one value for the whole site, resent and saved
    # the same whichever language the form is showing.
    def update
      site = Current.site
      permitted = params.fetch(:site_setting, ActionController::Parameters.new)
        .permit(*Settings::Save::TRANSLATED, :logo, :default_locale, :trash_retention_days, :time_zone,
          :ai_provider, :ai_model, :ai_api_key, social_links: [ [ :name, :url ] ])

      translated = permitted.slice(*Settings::Save::TRANSLATED).to_h
      attributes = permitted.except(:social_links, *Settings::Save::TRANSLATED).to_h

      # `drop_blank_file_params` (see its own doc comment, carried over from
      # `Admin::PagesController#update`) keeps this same PATCH -- resent in
      # full on *every* autosave, whichever field an editor actually
      # touched -- from silently detaching an already-attached logo the
      # moment a blank `logo` file input rides along with it. Removing one
      # on purpose is the explicit `remove_logo` checkbox instead.
      attributes = drop_blank_file_params(attributes, fields: %w[logo])
      attributes["logo"] = nil if !attributes.key?("logo") && ActiveModel::Type::Boolean.new.cast(params.dig(:site_setting, :remove_logo))
      logo_changing = attributes.key?("logo")
      attributes["social_link_rows"] = permitted[:social_links] if permitted.key?(:social_links)
      ai_key_touched = assign_ai_key(attributes)

      result = Settings::Save.call(site, attributes: attributes, translations: { admin_locale => translated })
      saved = result.ok?

      streams = autosave_stream(
        record: site,
        result: result,
        status_id: "#{ID_PREFIX}-save-status",
        error_prefix: ID_PREFIX,
        base_updated_at: params[:base_updated_at],
        fields: { title: [ :title ], tagline: [ :tagline ], logo: [ :logo ], default_locale: [ :default_locale ],
          trash_retention_days: [ :trash_retention_days ], time_zone: [ :time_zone ], social_links: [ :social_links ],
          ai_provider: [ :ai_provider ], ai_model: [ :ai_model ], ai_api_key: [ :ai_api_key ] }
      )

      streams << logo_field_stream(site) if saved && logo_changing
      # Saved or not: either way the field must come back empty (a refused
      # save mustn't leave a typed key sitting in the page), and the
      # section says what's stored now.
      streams << ai_key_field_stream(site) if ai_key_touched
      # First, so the status and error streams after it land in the new form.
      streams.unshift(form_stream(site)) if saved && site.saved_change_to_default_locale?

      render turbo_stream: streams, status: autosave_status(result)
    end

    # Test connection (translation helpers spec §6.2): one tiny request
    # with the *saved* provider, model and key (`AI.provider`, then the
    # provider's own `#test_connection`), reported inline under the button.
    # Writes nothing, so it's not a service; `settings.manage` is the
    # controller-wide `before_action` above.
    def test_ai_connection
      AI.provider.test_connection
      render turbo_stream: ai_test_result_stream(message: "Connection OK.", ok: true)
    rescue AI::Error => error
      render turbo_stream: ai_test_result_stream(message: error.message, ok: false), status: :unprocessable_entity
    end

    private

    # The API key's two rules (spec §6.2), applied to the attributes about
    # to go to `Settings::Save`: a blank `ai_api_key` keeps the stored key
    # (the field is always rendered empty, so blank means "not changing
    # it"), and `remove_ai_key` clears it -- unless a new key was typed in
    # the same submit, which wins, like a new logo over `remove_logo`.
    # Returns whether this request touched the key at all.
    def assign_ai_key(attributes)
      attributes.delete("ai_api_key") if attributes["ai_api_key"].blank?
      removing = ActiveModel::Type::Boolean.new.cast(params.dig(:site_setting, :remove_ai_key))
      attributes["ai_api_key"] = nil if removing && !attributes.key?("ai_api_key")

      attributes.key?("ai_api_key")
    end

    def ai_key_field_stream(site)
      turbo_stream.replace("#{ID_PREFIX}-ai-key-section", partial: "admin/settings/ai_key_field", locals: { site_setting: site })
    end

    def ai_test_result_stream(message:, ok:)
      turbo_stream.replace("#{ID_PREFIX}-ai-test-result", partial: "admin/settings/ai_test_result", locals: { message: message, ok: ok })
    end

    # A new default language changes what every translated field shows:
    # which language is the original, the originals beside the inputs, the
    # switcher's links and markers. The whole form is re-rendered, still in
    # the language it was being edited in (`admin_locale`, which the form
    # always posts).
    def form_stream(site)
      turbo_stream.replace(Admin::SettingsFormComponent::DOM_ID,
        Admin::SettingsFormComponent.new(site_setting: site, locale: admin_locale))
    end

    def forbidden_status_id = action_name == "update" ? "#{ID_PREFIX}-save-status" : nil

    # The logo section
    # (preview + "Remove image" checkbox) is the one part of this form a
    # plain autosave doesn't otherwise bring back in sync with what was
    # actually saved.
    def logo_field_stream(site)
      section_id = "#{ID_PREFIX}-logo-section"

      turbo_stream.replace(section_id, partial: "admin/shared/image_upload_field", locals: {
        section_id: section_id, name: "logo",
        image_id: "#{ID_PREFIX}-logo", image_html_name: "site_setting[logo]", image_value: site.logo,
        checkbox_id: "#{ID_PREFIX}-remove_logo", checkbox_html_name: "site_setting[remove_logo]",
        show_checkbox: site.logo.attached?
      })
    end
  end
end
