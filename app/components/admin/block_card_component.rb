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
  # "Unavailable type" card instead (danger border, one sentence, "Delete
  # block…" its only action).
  #
  # The header (design pass round 2): drag handle, the type name -- a button
  # that collapses the body (`aria-expanded`) -- and a "⋯" `Admin::MenuComponent`
  # (Move up, Move down, "Move into section…", Duplicate, a divider, "Delete
  # block…"). `first:` and
  # `last:` only decide whether Move up / Move down start disabled; the page
  # view and the controller's list re-render work them out, and `admin
  # --blocks#refreshMoveState` keeps them right in the browser after every
  # move, add and delete (an insertion streams one card in and touches no
  # other, so the neighbour's state can only be corrected there).
  #
  # A post-list block's Type, Tag and Limit share one row (`#settings_row?`),
  # Tag being a one-value `Admin::ChipInputComponent` over the tag
  # suggestions (no creating a tag from a filter).
  #
  # `editable:` is whether the user may change this page's blocks
  # (access-control design spec §5, `can_edit?` on the page -- blocks
  # follow their page's permissions). The page view works it out once and
  # hands it to every card; left nil, the card asks itself. A view-only
  # card has no drag handle, no "⋯" menu (Duplicate, Move, Delete) and its
  # form is disabled without `admin--autosave`.
  #
  # `placement:` is where the card is drawn (sections spec §4.3, D4):
  # - `:list`, the default, is everything above: a card of the page's block
  #   list;
  # - `:panel` is the same form for a block that sits in a section's column,
  #   drawn under the section's lanes and shown by pressing the block's tile
  #   (`Admin::EditorScreen::SectionCardComponent`, `admin--section`). It is
  #   this component and not a second form component on purpose: the form,
  #   its ids, its `base_updated_at`, its status line and its error slots are
  #   what `Admin::ContentBlocksController#update` answers into, and a block
  #   moved between the list and a column must be answered the same way. What
  #   differs is the frame around the form. The wrapper has its own id
  #   (`panel_id`, because `dom_id(block)` is the TILE's in a section) and is
  #   rendered `hidden`: every panel of a section is in the page from the
  #   start and `admin--section` only shows one, so a form is never fetched
  #   or removed and keeps its place in the write queue (see that script). It
  #   is no `card` of `admin--blocks` -- the section is the card -- and has no
  #   handle, no "⋯" menu and no delete dialog: a block in a column is moved,
  #   copied and deleted from its tile, which holds the dialog. Its
  #   header is a heading that says which column the form belongs to, and
  #   Close. `open: true` is for the panel of a block just added to a column
  #   (spec §4.3: it opens at once). The panel is still rendered `hidden`,
  #   with `data-open` beside it: showing a form is `admin--section`'s alone
  #   -- it closes the one that was open first, sending what that one holds
  #   -- so the server only asks, and the script takes the mark off as it
  #   opens. A panel shown by the markup would be a second open form;
  # - `:group` is a plain card with neither handle nor menu, for a block
  #   listed under a section's heading in the translation view (spec §4.5,
  #   `Admin::EditorScreen::SectionGroupComponent`). It has the block's
  #   `dom_id`, as there is no tile on that tab, and its form is the same
  #   autosave form with the same ids. Nothing in it opens a delete dialog,
  #   so it carries none -- except for a block whose type is gone, whose one
  #   action is "Delete block…" wherever it is drawn (spec §6) and which has
  #   no tile here to hold the dialog for it.
  class BlockCardComponent < AdminComponent
    PLACEMENTS = %i[list panel group].freeze

    # `"block-<id>"` is public so `Admin::ContentBlocksController` can
    # recompute the exact same ids from a plain controller method (the
    # save status and error slots its autosave stream targets) without a
    # second, hand-kept copy of this string drifting out of sync with it.
    def self.error_prefix(block) = "block-#{block.id}"

    # The panel's ids are public for the same reason: the block's tile names
    # the panel it opens (`aria-controls`), and a later stream targets it.
    def self.panel_id(block) = "#{error_prefix(block)}-panel"

    def self.panel_title_id(block) = "#{error_prefix(block)}-panel-title"

    # The ids of a block's autosave form, and the wiring of the form itself,
    # are the class's for the same reason again: a section's settings are a
    # form in its card's header (`Admin::EditorScreen::SectionCardComponent`),
    # not a block card, and `Admin::ContentBlocksController#update` answers a
    # section's save into the same three ids it answers a card's into.
    def self.status_id(block) = "#{error_prefix(block)}-save-status"

    def self.base_updated_at_id(block) = "#{error_prefix(block)}-base-updated-at"

    def self.autosave_form_data(block)
      {
        controller: "admin--autosave",
        action: "input->admin--autosave#queue change->admin--autosave#queue focusout->admin--autosave#saveNow",
        "admin--autosave-status-id-value": status_id(block),
        "admin--autosave-page-base-id-value": "#{Admin::PageSettingsFormComponent::ID_PREFIX}-base-updated-at"
      }
    end

    # A menu item's look in every menu of the block list -- a card's "⋯", a
    # section's, a lane's "+" (`Admin::BlockPickerComponent::MENU_ITEM_CLASS`
    # is this constant): the panel already styles its buttons (width,
    # padding, hover); a disabled one dims and drops the hover fill.
    MENU_ITEM_CLASS = "text-sm text-ink disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:bg-transparent".freeze

    def initialize(page:, block:, locale:, url_options: {}, first: false, last: false, editable: nil, placement: :list, open: false)
      raise ArgumentError, "unknown block card placement #{placement.inspect}" unless PLACEMENTS.include?(placement)

      @placement = placement
      @open = open
      @editable = editable
      @page = page
      @block = block
      @locale = locale
      @url_options = url_options
      @first = first
      @last = last
    end

    def dom_id = ActionView::RecordIdentifier.dom_id(block)

    def panel? = @placement == :panel

    def list? = @placement == :list

    def wrapper_id = panel? ? self.class.panel_id(block) : dom_id

    # What `admin--blocks` and `admin--section` find the wrapper by. Only a
    # card of the list is a `card` (dragged, moved, counted for Move up and
    # Move down); only a panel is hidden, and it is its section's to show.
    def wrapper_attributes
      return { hidden: true, **panel_name, data: { block_id: block.id, "admin--section-target": "panel", **(@open ? { open: true } : {}) } } if panel?

      { data: { block_id: block.id, **(list? ? { "admin--blocks-target": "card" } : {}), **(note_menu? ? {} : { notes_add: "shown" }) } }
    end

    # The panel is the region its tile's `aria-controls` points at, named by
    # its own heading -- which an unavailable block's panel doesn't have.
    def panel_name = unavailable? ? {} : { role: "region", aria: { labelledby: self.class.panel_title_id(block) } }

    # "Image · column 2" (spec §4.3), drawn by the component a stream
    # redraws it with when the block's column changes under the open form.
    def panel_title = Admin::EditorScreen::PanelTitleComponent.new(block: block)

    def definition = block.definition

    def unavailable? = definition.nil?

    def label = definition&.label || block.block_type

    def unavailable_label = "Unavailable type — #{block.block_type}"

    def first? = @first

    def last? = @last

    def editable? = @editable.nil? ? (@editable = can_edit?(page)) : @editable

    def form_data = editable? ? self.class.autosave_form_data(block) : {}

    def error_prefix = self.class.error_prefix(block)

    def status_id = self.class.status_id(block)

    def base_updated_at_id = self.class.base_updated_at_id(block)

    def base_updated_at_value = block.updated_at.iso8601(6)

    def form_url = helpers.admin_page_content_block_path(page, block, **url_options)

    def duplicate_path = helpers.duplicate_admin_page_content_block_path(page, block, **url_options)

    # The block's "Delete this block?" (`DeleteBlockDialogComponent`): drawn
    # in the card -- and for a block in a column in its TILE, never in its
    # panel, which is hidden while its form is closed (`delete_dialog?`).
    def delete_dialog = Admin::EditorScreen::DeleteBlockDialogComponent.new(page: page, block: block, url_options: url_options)

    def delete_dialog_id = Admin::EditorScreen::DeleteBlockDialogComponent.dialog_id(block)

    # The block's notes marker (`Admin::NotesScreen::MarkerComponent`, notes
    # spec §4.3): on a card of the list and on a translation tab's group
    # card, for every viewer. Not on a panel -- the block's tile carries it,
    # and two markers of one block would be two elements with one id -- and
    # not on an unavailable block's card, which has one action.
    def note_marker = Admin::NotesScreen::MarkerComponent.new(subject: block, name: label)

    def note_key = ::Notes.key(block)

    # Whether this card has a "⋯" menu, whose first item is "Add note". Where
    # it has none -- a viewer who can't edit, a translation tab's group card --
    # the marker of a block without notes is the only way to start one, so it
    # is shown at rest and not only on hover or focus (`data-notes-add`, read
    # by `.admin-notes-marker`'s rules): who can read can write notes
    # (decision D3), and a touch screen has no hover.
    def note_menu? = list? && editable? && !unavailable?

    # A card of the list always has it (its menu opens it). A group card only
    # when the block is unavailable: the header's "Delete block…" is then the
    # one thing that opens it.
    def delete_dialog? = editable? && (list? || (!panel? && unavailable?))

    # "Move into section…" (sections spec §4.4): for a card of the page's own
    # list that is no container -- a section never holds a section. See the
    # template for why it starts disabled.
    def move_into? = list? && !block.container?

    def move_into = Admin::EditorScreen::MoveDialogComponent.trigger("into")

    def body_id = "#{error_prefix}-body"

    def menu_item_class = MENU_ITEM_CLASS

    # The row-shaped settings of a post list (handoff B22): its three
    # settings side by side, in this order, whatever order the type declared
    # them in. Only where the schema fields are inputs (not on a translation
    # tab, where untranslated fields are listed read-only) and only for a
    # type that lists posts -- its `content_type`, `tag` and `limit` are
    # required by `BlockTypeDefinition#finalize!`.
    SETTINGS_ROW = %w[content_type tag limit].freeze

    def settings_row? = !unavailable? && definition.capability?(:lists_posts) && !translation_tab? && settings_row_fields.size == SETTINGS_ROW.size

    def settings_row_fields = SETTINGS_ROW.filter_map { |name| schema_fields.find { |field| field.name == name } }

    # Everything else in the schema, rendered one per line as before.
    def other_schema_fields = settings_row? ? schema_fields - settings_row_fields : schema_fields

    # Where the row's Tag chip input asks for suggestions: the same
    # endpoint the post editor's tags use, open to `pages.edit` as well as
    # `posts.read`/`tags.manage` (`Admin::TagSuggestionsController`), so an
    # editor of this page's blocks can always list the tags.
    def tag_search_url = helpers.admin_tag_suggestions_path(**url_options)

    def tag_chips(field)
      tag = value_for(field).to_s
      tag.present? ? [ { value: tag, label: tag } ] : []
    end

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
    # instead be listed read-only under "Shared fields" on a translation tab
    # (`#shared_fields`).
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
    def translation(field) = Admin::EditorScreen::ReferenceCardComponent.options_for(block, field, locale: locale, confirmable: editable?)

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
