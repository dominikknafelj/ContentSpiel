module Admin
  module EditorScreen
    # The post editor (cs-studio spec §5.2): the same header (`Admin::
    # EditorScreen::HeaderComponent`, which it renders first), autosave and
    # publish-state behaviour as the page editor (+ `Admin::
    # EditorScreen::PageSettingsFormComponent`), folded into one component -- there is
    # exactly one post form per screen (unlike a page,
    # which shares the tree column with every other page, or a block, which
    # can have several cards on one page at once), so there's no multi-
    # instance-per-screen id collision to disambiguate against the way
    # `EditorScreen::BlockCardComponent`'s own `error_prefix` does. Every id here is the bare
    # literal "post" (`ID_PREFIX`), matching `Admin::PostsController`'s own
    # `autosave_stream(error_prefix: "post", ...)` and `post_error_fields`.
    class PostFormComponent < AdminComponent
      ID_PREFIX = "post"

      # `slot_context` is the header's (`HeaderComponent`): what the screen has
      # already read that a feature at the header's slots would read again.
      def initialize(post:, locale:, url_options: {}, slot_context: {}, form_only: false, holds: nil)
        @post = post
        @locale = locale
        @url_options = url_options
        @slot_context = slot_context
        @form_only = form_only
        @holds = holds
      end

      # The answer to `Admin::EditingController#record`: the form alone, without
      # the header above it, which nothing fetches.
      def form_only? = @form_only

      def save_status_id = "post-save-status"

      def base_updated_at_id = "#{ID_PREFIX}-base-updated-at"

      def base_updated_at_value = post.updated_at.iso8601(6)

      def form_url = helpers.admin_post_path(post, **url_options)

      def definition = post.definition

      # Access control (design spec §5 "Everywhere"): `editable?` is whether the
      # form itself is live: without it the header says "View only", every
      # field is disabled (one `<fieldset disabled>` around the form's
      # contents, which also makes the rich-text editor read-only) and
      # `admin--saving--autosave` isn't attached, so typing sends nothing at all
      # (Review Focus 4).
      def editable? = defined?(@editable) ? @editable : (@editable = can_edit?(post))

      # The post is held as a whole (one subject, "record"); the strip stands
      # in the header's notice area (`HoldStripComponent.slot_id`). A viewer
      # who may only read sees it without "Take over" (handoff 26).
      def holds = @holds ||= ::Editing::Holds.on(post, viewer: Current.user, tab: Current.editing_tab)

      def hold = holds.other(post)

      def held? = hold.present?

      def read_only_hold? = held? && editable?

      def hold_strip = Admin::EditorScreen::HoldStripComponent.new(subject: post, hold: hold, viewer: Current.user, own: holds.own_user?(hold), take_over: editable?)

      def editing_version = ::Editing.version(post, hold: hold, take_over: editable?)

      def held_marks = held? ? { editing_held: true } : {}

      def fields(&content) = read_only_hold? ? Admin::EditorScreen::HeldFields.call(capture(&content), guard: true) : capture(&content)

      # The form's `data-*`: the autosave wiring only when the post is
      # editable (see `editable?`) and nobody else holds it.
      def form_data
        return {} if !editable? || read_only_hold?

        {
          controller: "admin--saving--autosave",
          action: "input->admin--saving--autosave#queue change->admin--saving--autosave#queue focusout->admin--saving--autosave#saveNow",
          "admin--saving--autosave-status-id-value": save_status_id
        }
      end

      # See `Admin::EditorScreen::PageSettingsFormComponent#translation`.
      def translation(field) = Admin::EditorScreen::ReferenceCardComponent.options_for(post, field, locale: locale, confirmable: editable? && !read_only_hold?)

      def field_id(name) = "#{ID_PREFIX}-#{name}"

      def field_html_name(name) = "post[#{name}]"

      def field_errors(name) = post.errors.full_messages_for(name)

      # A post's own value in whichever locale is being edited -- Mobility's
      # per-locale accessor, not the plain reader, same reasoning `Admin::
      # EditorScreen::PageSettingsFormComponent#value` gives (config/initializers/mobility.rb
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

      # The typed fields rendered as inputs. On a translation tab only the
      # translated ones: an untranslated field is the same in every language, so
      # it is shown read-only in `#shared_fields` instead of being a form input
      # (see `Admin::EditorScreen::SharedFieldsComponent`).
      def schema_fields
        fields = definition&.fields || []
        translation_tab? ? fields.select(&:translated?) : fields
      end

      def translation_tab? = locale.to_s != ::Locales.default

      # The type's own fields (and, on a translation tab, the read-only list of
      # the ones shared by every language) are one titled group; a type with
      # none draws no empty group.
      def fields_group? = schema_fields.any? || shared_fields.any?

      def fields_group_title = "#{definition&.label || post.content_type.to_s.humanize} fields"

      # `[label, value]` for every untranslated field, read from the original
      # language (an untranslated field's one value lives there). Empty off a
      # translation tab, where those fields are ordinary inputs.
      def shared_fields
        return [] unless translation_tab?

        (definition&.fields || []).reject(&:translated?).map do |field|
          [ field.name.humanize, Admin::EditorScreen::SharedFieldsComponent.display(field, default_fields_object&.public_send(field.name)) ]
        end
      end

      # This post's own typed-field value, in whichever locale is being
      # edited -- `fields(locale:)` reads the *literal* locale (no fallback
      # chain), the same admin/MCP rule `Admin::EditorScreen::BlockCardComponent#value_for`
      # is built around for a block's own schema fields.
      def field_value(field) = fields_object&.public_send(field.name)

      # `field.translated?` gates this first -- same fix, same reasoning,
      # `Admin::EditorScreen::BlockCardComponent#original_for`'s own comment gives: an
      # untranslated typed field (e.g. `test/event`'s own `venue`) has one
      # value across every locale, so it be listed read-only under
      # "Shared fields" (`#shared_fields`), not shown as an original that would
      # otherwise show up here regardless of `translated?`.
      def field_original(field)
        return nil if !field.translated? || locale.to_s == ::Locales.default

        default_fields_object&.public_send(field.name)
      end

      def field_errors_for(field) = post.errors.full_messages_for("fields.#{field.name}")

      def tag_chips = post.tags.order(:name).map { |tag| { value: tag.name, label: tag.name } }

      private

      attr_reader :post, :locale, :url_options

      def urls = PublicSite::Urls.new

      def fields_object = post.fields(locale: locale)

      def default_fields_object = post.fields(locale: ::Locales.default)
    end
  end
end
