module Admin
  # One block's card in the page editor's block list (cs-studio spec §5.1):
  # its type label, drag handle, collapse toggle and "⋯" menu (Duplicate,
  # Move up/down, Delete), plus its own autosaving form -- the schema fields
  # from `block.definition.fields` (`Admin::FieldComponent`) and the columns
  # it opts into (`block.definition.uses_columns`, one `Admin::Columns::*`
  # each). Mirrors `Admin::PageSettingsFormComponent`'s shape (one `<form
  # data-controller="admin--autosave">`, a hidden `base_updated_at`, a
  # `save-status` line) but there can be many of these on one page at once,
  # unlike the page settings form -- every id here is therefore built off
  # `error_prefix` (`"block-<id>"`, unique per row) rather than a bare,
  # hand-kept string like `"page"`, and every `Admin::FieldComponent` this
  # renders is handed that same prefix via `id_prefix:` so two blocks of the
  # *same* type on one page never render two inputs (or two Turbo Stream
  # error-replace targets) sharing one id -- see that component's own
  # comment for why its default `dom_id_prefix(form_name)` alone isn't
  # enough once `form_name` ("block[settings]") is the same literal string
  # on every card.
  #
  # A block whose stored `block_type` isn't (or is no longer) registered --
  # a removed plugin, spec §8 -- has no `definition` to read a schema or
  # columns from: `unavailable?` switches the template to the minimal
  # "Unavailable type" card instead, Delete its only action.
  #
  # `editable:` is whether the user may change this page's blocks
  # (access-control design spec §5, `can_edit?` on the page -- blocks
  # follow their page's permissions). The page view works it out once and
  # hands it to every card; left nil, the card asks itself. A view-only
  # card has no drag handle, no "⋯" menu (Duplicate, Move, Delete), no
  # "+" picker below it, and its form is disabled without `admin--autosave`.
  class BlockCardComponent < AdminComponent
    # `"block-<id>"` is public so `Admin::ContentBlocksController` can
    # recompute the exact same ids from a plain controller method (the
    # save status and error slots its autosave stream targets) without a
    # second, hand-kept copy of this string drifting out of sync with it.
    def self.error_prefix(block) = "block-#{block.id}"

    def initialize(page:, block:, locale:, url_options: {}, last: false, editable: nil)
      @editable = editable
      @page = page
      @block = block
      @locale = locale
      @url_options = url_options
      @last = last
    end

    def dom_id = ActionView::RecordIdentifier.dom_id(block)

    def definition = block.definition

    def unavailable? = definition.nil?

    def label = definition&.label || block.block_type

    def unavailable_label = "Unavailable type — #{block.block_type}"

    def last? = @last

    def editable? = @editable.nil? ? (@editable = can_edit?(page)) : @editable

    def form_data
      return {} unless editable?

      {
        controller: "admin--autosave",
        action: "input->admin--autosave#queue change->admin--autosave#queue focusout->admin--autosave#saveNow",
        "admin--autosave-status-id-value": status_id,
        "admin--autosave-page-base-id-value": "#{Admin::PageSettingsFormComponent::ID_PREFIX}-base-updated-at"
      }
    end

    def error_prefix = self.class.error_prefix(block)

    def status_id = "#{error_prefix}-save-status"

    def base_updated_at_id = "#{error_prefix}-base-updated-at"

    def base_updated_at_value = block.updated_at.iso8601(6)

    def form_url = helpers.admin_page_content_block_path(page, block, **url_options)

    def duplicate_path = helpers.duplicate_admin_page_content_block_path(page, block, **url_options)

    def destroy_path = helpers.admin_page_content_block_path(page, block, **url_options)

    def delete_dialog_id = "delete-block-#{block.id}"

    def field_id(name) = "#{error_prefix}-#{name}"

    def field_html_name(name) = "block[#{name}]"

    # The schema fields rendered as inputs: on a translation tab only the
    # translated ones -- an untranslated field is the same in every language,
    # so it is listed read-only by `#shared_fields` instead of being an input
    # a translation tab's autosave could send (and change) by accident.
    def schema_fields
      translation_tab? ? definition.fields.select(&:translated?) : definition.fields
    end

    def translation_tab? = locale.to_s != ::Locales.default

    # `[label, value]` for each untranslated schema field, read from the
    # primary language (where its one value lives); empty off a translation tab.
    def shared_fields
      return [] unless translation_tab?

      definition.fields.reject(&:translated?).map do |field|
        [ field.name.humanize, Admin::EditorScreen::SharedFieldsComponent.display(field, default_settings_object&.public_send(field.name)) ]
      end
    end

    # This block's own value for a schema field, in whichever locale is
    # being edited -- `settings_object(locale:)` reads the *literal* locale
    # (no fallback chain), the same admin/MCP rule `ContentBlock`'s own
    # `settings_are_valid` is built around, so a blank German `text` renders
    # blank here rather than silently showing the English one.
    def value_for(field) = settings_object&.public_send(field.name)

    # The default-language value for a translated schema field, shown
    # read-only once the editing locale isn't the default one (spec §6.2) --
    # same `nil`-means-"nothing to compare against" contract
    # `Admin::FieldComponent#show_original?` already reads off this.
    #
    # `field.translated?` gates this first: an *untranslated* schema field
    # (e.g. a post_list block's own `limit`) has exactly one value across
    # every locale, so its default-locale value is never "the original to
    # translate from" -- returning it here regardless of `translated?` (the
    # bug this guard fixes) would make `FieldComponent#show_original?` show
    # a read-only original/translate-slot pair for a field that should
    # instead render its "Same in all languages" hint
    # (`FieldComponent#show_untranslated_hint?`, which itself only fires
    # once this method hands back nil).
    def original_for(field)
      return nil if !field.translated? || locale.to_s == ::Locales.default

      default_settings_object&.public_send(field.name)
    end

    def field_errors(field) = block.errors.full_messages_for("settings.#{field.name}")

    def uses_columns = definition.uses_columns

    # `"body"` is the rich-text JSON document (tiptap spec §3.1), read
    # through `body_document` (a `RichText::Document`) rather than the raw
    # Mobility accessor.
    def column_value(name)
      # The block's library image (`Admin::Columns::MediaColumnComponent`).
      return block.media_asset if name == "image"
      return block.body_document(locale: locale) if name == "body"

      block.public_send(name, locale: locale)
    end

    def column_original(name)
      return nil if name == "image" || locale.to_s == ::Locales.default
      return block.body_document(locale: ::Locales.default) if name == "body"

      block.public_send(name, locale: ::Locales.default)
    end

    def column_errors(name) = block.errors.full_messages_for(name)

    # See `Admin::PageSettingsFormComponent#translation` -- a block's own
    # fields, confirmed on the block (`block.translation_confirmed`), with
    # the page's edit right (`editable?`, blocks follow their page).
    def translation(field) = Admin::TranslationScreen::OutdatedNoteComponent.options_for(block, field, locale: locale, confirmable: editable?)

    # The caption/alt fields are this block's per-use overrides of its
    # image's own defaults (media library design spec §6): blank, the
    # public page falls back to the image's default in this language, which
    # is what they show as their placeholder (kept current after a pick by
    # `admin--media-field`, through the `placeholder_ids:` that
    # `.image_field` below hands the image column).
    def column_placeholder(name)
      case name
      when "alt" then Admin::Columns::MediaColumnComponent.default_alt(block.media_asset, locale)
      when "caption" then Admin::Columns::MediaColumnComponent.default_caption(block.media_asset, locale)
      end
    end

    # The image column itself -- a class method so `Admin
    # ::ContentBlocksController` re-renders a refused choice from exactly
    # what this card renders (`asset` passed in: after a refusal that's the
    # *stored* image). Its placeholder ids are whichever override fields
    # the block's type actually renders -- a type that `uses :image`
    # without `:alt` or `:caption` has none to update.
    def self.image_field(block:, asset:, locale:, errors: [])
      prefix = error_prefix(block)
      uses = block.definition&.uses_columns || []

      Admin::Columns::MediaColumnComponent.new(
        name: "image", id: "#{prefix}-image", html_name: "block[media_asset_id]",
        value: asset, errors: errors, locale: locale, section_id: "#{prefix}-image-section",
        placeholder_ids: (%w[alt caption] & uses).to_h { |column| [ column, "#{prefix}-#{column}" ] }
      )
    end

    private

    attr_reader :page, :block, :locale, :url_options

    def settings_object = block.settings_object(locale: locale)

    def default_settings_object = block.settings_object(locale: ::Locales.default)
  end
end
