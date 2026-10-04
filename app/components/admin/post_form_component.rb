module Admin
  # The post editor (cs-studio spec §5.2): the same shell, autosave and
  # publish-state behaviour as the page editor (`Admin::RecordHeaderComponent`
  # + `Admin::PageSettingsFormComponent`), folded into one component the way
  # `Admin::BlockCardComponent` already folds a block's own header and form
  # together -- there is exactly one post form per screen (unlike a page,
  # which shares the tree column with every other page, or a block, which
  # can have several cards on one page at once), so there's no multi-
  # instance-per-screen id collision to disambiguate against the way
  # `BlockCardComponent`'s own `error_prefix` does. Every id here is the bare
  # literal "post" (`ID_PREFIX`), matching `Admin::PostsController`'s own
  # `autosave_stream(error_prefix: "post", ...)` and `post_error_fields`.
  class PostFormComponent < AdminComponent
    ID_PREFIX = "post"

    def initialize(post:, locale:, url_options: {})
      @post = post
      @locale = locale
      @url_options = url_options
    end

    def status = post.status

    def live? = post.live?

    def scheduled_at = post.published_at

    def save_status_id = "post-save-status"

    def base_updated_at_id = "#{ID_PREFIX}-base-updated-at"

    def base_updated_at_value = post.updated_at.iso8601(6)

    def form_url = helpers.admin_post_path(post, **url_options)

    def definition = post.definition

    # The canonical address (spec §5.2): a `post_list` block somewhere lists
    # this post, or it doesn't -- `nil` here means "nowhere yet", the same
    # contract `PublicSite::Urls#path_for` already uses for a page with no
    # path, told apart in the template by the "Not listed on any page yet"
    # message the spec calls for verbatim.
    def public_path = urls.path_for(post, locale)

    def public_url = urls.url_for(post, locale)

    def preview_path = preview_urls.path_for(post, locale)

    # Access control (design spec §5 "Everywhere"): Publish now, Unpublish
    # and Schedule… need `posts.publish` on this post, Delete `posts.delete`
    # -- each absent, not disabled, without it. `editable?` is whether the
    # form itself is live: without it the header says "View only", every
    # field is disabled (one `<fieldset disabled>` around the form's
    # contents, which also makes the rich-text editor read-only) and
    # `admin--autosave` isn't attached, so typing sends nothing at all
    # (Review Focus 4).
    def editable? = defined?(@editable) ? @editable : (@editable = can_edit?(post))

    def may_publish? = can?("posts.publish", post)

    def can_publish? = !post.live? && may_publish?

    def can_unpublish? = post.status != "draft" && may_publish?

    def can_delete? = can?("posts.delete", post)

    # The form's `data-*`: the autosave wiring only when the post is
    # editable (see `editable?`).
    def form_data
      return {} unless editable?

      {
        controller: "admin--autosave",
        action: "input->admin--autosave#queue change->admin--autosave#queue focusout->admin--autosave#saveNow",
        "admin--autosave-status-id-value": save_status_id
      }
    end

    def delete_dialog_id = "delete-post-#{post.id}"

    def scheduled_at_input_value
      (post.status == "scheduled" ? post.published_at : Time.current + 1.day).strftime("%Y-%m-%dT%H:%M")
    end

    # The dot-marked codes for `Admin::LanguageTabsComponent` (spec
    # §6.2) -- same reasoning `Admin::RecordHeaderComponent#missing_locales`
    # gives for its own page.
    def missing_locales = switcher_locales[:missing]

    # The switcher's "original changed" codes (translation helpers spec §4).
    def outdated_locales = switcher_locales[:outdated]

    # See `Admin::RecordHeaderComponent#switcher_locales`.
    def switcher_locales = @switcher_locales ||= Translations::Status.switcher_locales(post)

    # See `Admin::PageSettingsFormComponent#translation`.
    def translation(field) = Admin::TranslationScreen::OutdatedNoteComponent.options_for(post, field, locale: locale, confirmable: editable?)

    # Per-code URL for the switcher: same "omit `locale:` for the site's
    # default language" rule `Admin::RecordHeaderComponent#language_url`
    # applies to a page, rebuilt here against this post's own editor path.
    def language_url
      ->(code) { helpers.admin_post_path(post, **(code.to_s == ::Locales.default ? {} : { locale: code })) }
    end

    def field_id(name) = "#{ID_PREFIX}-#{name}"

    def field_html_name(name) = "post[#{name}]"

    def field_errors(name) = post.errors.full_messages_for(name)

    # A post's own value in whichever locale is being edited -- Mobility's
    # per-locale accessor, not the plain reader, same reasoning `Admin::
    # PageSettingsFormComponent#value` gives (config/initializers/mobility.rb
    # turns off the plain reader's own cross-locale fallback deliberately).
    #
    # `:body` is the rich-text JSON document (tiptap spec §3.1), read through
    # `body_document` -- the model's own seam that turns the stored Hash
    # into a `RichText::Document` -- rather than the raw Mobility accessor.
    def value(column)
      return post.body_document(locale: locale) if column == :body

      post.public_send(column, locale: locale)
    end

    # The default-language value, shown read-only beside a translated column
    # whenever the editing locale isn't already the default one (spec §6.2)
    # -- nil in the default locale itself, which is what tells `Admin::
    # Columns::Base#show_original?` there's nothing to compare against.
    def original(column)
      return nil if locale.to_s == ::Locales.default
      return post.body_document(locale: ::Locales.default) if column == :body

      post.public_send(column, locale: ::Locales.default)
    end

    # The parent the slug preview line appends to: this post's own canonical
    # listing page, resolved through `PublicSite::Paths.canonical_page`
    # (spec §5.3's own ranking) rather than anything this component would
    # have to re-derive -- blank when there isn't one yet (an unlisted post,
    # or a listed one whose own page currently has no path mid-move), which
    # just leaves the preview line showing the bare slug with nothing in
    # front of it.
    def slug_base_url
      page = PublicSite::Paths.canonical_page(post)
      # No trailing slash: the listing page at "/" (or "/de/") would otherwise
      # put "//slug" on screen (design pass bug 1); the slug field appends its own "/".
      page ? (urls.path_for(page, locale) || "").sub(%r{/+\z}, "") : ""
    end

    def schema_fields = definition&.fields || []

    # This post's own typed-field value, in whichever locale is being
    # edited -- `fields(locale:)` reads the *literal* locale (no fallback
    # chain), the same admin/MCP rule `Admin::BlockCardComponent#value_for`
    # is built around for a block's own schema fields.
    def field_value(field) = fields_object&.public_send(field.name)

    # `field.translated?` gates this first -- same fix, same reasoning,
    # `Admin::BlockCardComponent#original_for`'s own comment gives: an
    # untranslated typed field (e.g. `test/event`'s own `venue`) has one
    # value across every locale, so it must fall through to `FieldComponent
    # #show_untranslated_hint?`'s "Same in all languages" line, not a
    # read-only original that would otherwise show up here regardless of
    # `translated?`.
    def field_original(field)
      return nil if !field.translated? || locale.to_s == ::Locales.default

      default_fields_object&.public_send(field.name)
    end

    def field_errors_for(field) = post.errors.full_messages_for("fields.#{field.name}")

    def tag_names_value = post.tags.order(:name).map(&:name).join(", ")

    private

    attr_reader :post, :locale, :url_options

    # Absolute addresses (the "Copy" button) use the configured public
    # origin, or -- with none configured, as on a local checkout -- the
    # origin this very request came in on, which is where the site is
    # actually being served.
    def urls = PublicSite::Urls.new(host: PublicSite::Urls.configured_host || helpers.request.base_url)

    def preview_urls = PublicSite::Urls.new(preview: true)

    def fields_object = post.fields(locale: locale)

    def default_fields_object = post.fields(locale: ::Locales.default)
  end
end
