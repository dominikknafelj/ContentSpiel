module Admin
  # The page editor's "Page settings" panel (cs-studio spec §5.1): title,
  # slug + a live URL preview, page type, subtitle, hero image (a library
  # image, chosen through `Media::PickerComponent`) + alt
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

    # The hero field itself -- a class method so `Admin::PagesController`
    # re-renders a refused choice from exactly what this form renders
    # (`asset` passed in: after a refusal that's the *stored* hero, not
    # whatever the page now holds in memory).
    def self.hero_image_field(asset:, locale:, errors: [])
      Admin::Columns::MediaColumnComponent.new(
        name: "hero_image", id: "#{ID_PREFIX}-hero_image", html_name: "page[hero_media_asset_id]",
        value: asset, locale: locale, errors: errors, section_id: "#{ID_PREFIX}-hero-image-section",
        placeholder_ids: { alt: "#{ID_PREFIX}-hero_alt" }
      )
    end

    # `hero_alt` is the page's per-use override of the hero image's own
    # alt text (media library design spec §6): blank, the public page
    # falls back to the image's default in this language, which is what
    # the field shows as its placeholder.
    def hero_alt_placeholder = Admin::Columns::MediaColumnComponent.default_alt(page.hero_media_asset, locale)

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

    # The "Original changed" note's options for a translated field
    # (translation helpers spec §4) -- see `Admin::TranslationScreen
    # ::OutdatedNoteComponent.options_for`.
    def translation(field) = Admin::TranslationScreen::OutdatedNoteComponent.options_for(page, field, locale: locale, confirmable: editable?)

    # The homepage has no slug of its own (`Page#generates_slugs?`) -- its
    # path is "/" by design, so there's nothing here for an editor to type.
    def show_slug? = page.parent_id.present?

    # The parent's own current path, in this locale -- what the slug field
    # appends to (`Admin::Columns::SlugColumnComponent`'s own doc comment).
    # Only ever called when `show_slug?` is true, so `page.parent` is never
    # nil here.
    # Never ends in a slash -- the root page's path is "/", which would
    # otherwise show "//slug" in front of its children (design pass bug 1).
    def slug_base_url = (PublicSite::Urls.new.path_for(page.parent, locale) || "").sub(%r{/+\z}, "")

    def translation_tab? = locale.to_s != ::Locales.default

    def page_type_options = Page.page_types.keys.map { |key| [ key.humanize, key ] }

    def landing? = page.landing?

    # A page the user can read but not edit (access-control design spec §5,
    # `can_edit?`: `pages.edit`, plus `pages.publish` once published): every
    # field disabled by one `<fieldset disabled>`, and no `admin--autosave`,
    # so nothing is ever sent (Review Focus 4). `Admin::EditorScreen::HeaderComponent`
    # shows the "View only" badge above.
    def editable? = defined?(@editable) ? @editable : (@editable = can_edit?(page))

    def form_data
      return {} unless editable?

      {
        controller: "admin--autosave",
        action: "input->admin--autosave#queue change->admin--autosave#queue focusout->admin--autosave#saveNow autosave:flush@document->admin--autosave#flush",
        "admin--autosave-status-id-value": status_id
      }
    end

    private

    attr_reader :page, :locale, :url_options
  end
end
