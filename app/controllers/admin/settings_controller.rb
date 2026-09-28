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

    def show
      @site_setting = Current.site
    end

    # The settings form's own autosave endpoint (spec §6.1), same shape as
    # `Admin::PagesController#update`: every field in `params[:site_setting]`
    # PATCHes here together, answered with the shared Turbo Stream response
    # regardless of success.
    def update
      site = Current.site
      permitted = params.fetch(:site_setting, ActionController::Parameters.new)
        .permit(:title, :tagline, :logo, :default_locale, social_links: [ [ :name, :url ] ])

      attributes = permitted.except(:social_links).to_h

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

      result = Settings::Save.call(site, attributes: attributes)
      saved = result.ok?

      streams = autosave_stream(
        record: site,
        result: result,
        status_id: "#{ID_PREFIX}-save-status",
        error_prefix: ID_PREFIX,
        base_updated_at: params[:base_updated_at],
        fields: { title: [ :title ], tagline: [ :tagline ], logo: [ :logo ], default_locale: [ :default_locale ], social_links: [ :social_links ] }
      )

      streams << logo_field_stream(site) if saved && logo_changing

      render turbo_stream: streams, status: (saved ? :ok : :unprocessable_entity)
    end

    private

    # Mirrors `Admin::PagesController#hero_image_stream`: the logo section
    # (preview + "Remove image" checkbox) is the one part of this form a
    # plain autosave doesn't otherwise bring back in sync with what was
    # actually saved.
    def logo_field_stream(site)
      section_id = "#{ID_PREFIX}-logo-section"

      turbo_stream.replace(section_id, partial: "admin/shared/hero_image_field", locals: {
        section_id: section_id, name: "logo",
        image_id: "#{ID_PREFIX}-logo", image_html_name: "site_setting[logo]", image_value: site.logo,
        checkbox_id: "#{ID_PREFIX}-remove_logo", checkbox_html_name: "site_setting[remove_logo]",
        show_checkbox: site.logo.attached?
      })
    end
  end
end
