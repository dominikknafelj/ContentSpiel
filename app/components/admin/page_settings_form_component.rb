module Admin
  # The page editor's "Page settings" panel (cs-studio spec §5.1): title,
  # slug + a live URL preview, page type, subtitle, hero image + alt
  # (landing pages only), and meta title/description under "SEO" -- one
  # autosaving `<form>` (spec §6.1), PATCHing `Admin::PagesController#update`
  # on every field's `input`/`change` (debounced) or `focusout` (immediate).
  #
  # Every field's `id:` here is dash-joined (`page-title`, never
  # `page[title]`) so it doubles as this form's own Turbo Stream error-slot
  # id, via the exact formula `Admin::AutosaveResponses` computes
  # replacement targets with (`Admin::FieldComponent.error_id("page",
  # field)`) -- see `Admin::Columns::Base`'s own comment for why the id and
  # the submitted form field name (`html_name:`, bracket notation, so
  # `Admin::PagesController#update` sees a nested `params[:page]` hash) have
  # to be two different strings rather than one.
  class PageSettingsFormComponent < AdminComponent
    ID_PREFIX = "page"

    def initialize(page:, locale:, url_options: {})
      @page = page
      @locale = locale
      @url_options = url_options
    end

    def form_url = helpers.admin_page_path(page, **url_options)

    def status_id = "page-save-status"

    def base_updated_at_id = "#{ID_PREFIX}-base-updated-at"

    def base_updated_at_value = page.updated_at.iso8601(6)

    # The one `id` `Admin::PagesController#hero_image_stream` (Task 4 fix
    # round 2) needs to know ahead of time, since it re-renders this
    # section from a plain controller method rather than this component --
    # `ID_PREFIX` is public for exactly that: the two builders of this id
    # (this component's normal GET render, that controller's post-save
    # stream) share the one constant rather than each hand-keeping "page".
    def hero_image_section_id = "#{ID_PREFIX}-hero-image-section"

    def field_id(field) = "#{ID_PREFIX}-#{field}"

    def field_html_name(field) = "page[#{field}]"

    # The one non-`Admin::Columns::*` field this form renders by hand
    # (`page_type`'s `<select>`) still needs an error slot id that agrees
    # with `Admin::AutosaveResponses`, so it goes through the exact same
    # formula every other field's id already matches.
    def errors_id(field) = Admin::FieldComponent.error_id(ID_PREFIX, field)

    # A page's own value in whichever locale is being edited -- Mobility's
    # per-locale accessor (`page.title(locale: "de")`), not the plain reader:
    # config/initializers/mobility.rb turns off that reader's own fallback,
    # for exactly this reason -- a blank German title has to render as
    # blank here, not silently show the English one in its place.
    def value(field) = page.public_send(field, locale: locale)

    # The default-language value, shown read-only beside a translated field
    # whenever the editing locale isn't already the default one (spec §6.2)
    # -- nil in the default locale itself, which is what tells
    # `Admin::Columns::Base#show_original?` there's nothing to compare
    # against.
    def original(field)
      return nil if locale.to_s == ::Locales.default

      page.public_send(field, locale: ::Locales.default)
    end

    # The homepage has no slug of its own (`Page#generates_slugs?`) -- its
    # path is "/" by design, so there's nothing here for an editor to type.
    def show_slug? = page.parent_id.present?

    # The parent's own current path, in this locale -- what the slug field
    # appends to (`Admin::Columns::SlugColumnComponent`'s own doc comment).
    # Only ever called when `show_slug?` is true, so `page.parent` is never
    # nil here.
    def slug_base_url = PublicSite::Urls.new.path_for(page.parent, locale) || ""

    def page_type_options = Page.page_types.keys.map { |key| [ key.humanize, key ] }

    def landing? = page.landing?

    private

    attr_reader :page, :locale, :url_options
  end
end
