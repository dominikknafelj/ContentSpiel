module Admin
  module EditorScreen
    # A section in the page editor's block list (sections spec §4.1–§4.3): a
    # card like any other block's -- it is dragged, moved and collapsed by
    # `admin--blocks` exactly as one -- but framed and tinted, and holding the
    # section's columns as lanes of tiles (`SectionLanesComponent`) in its
    # body, where a block card has its fields. Its own three settings are a
    # form in its header (below).
    #
    # EVERY BLOCK'S FORM IS RENDERED WITH THE PAGE (plan decision D3). Under
    # the lanes sits one `Admin::EditorScreen::BlockCardComponent` per block of the section,
    # drawn as a `placement: :panel`: hidden, and shown one at a time by
    # `admin--section` when its tile is pressed. A form is never fetched when
    # a tile is opened and never removed when it is closed. That is what makes
    # the pattern safe on top of autosave: each form registers with the write
    # queue once (`admin--autosave`'s `connect`), and its debounce, its queued
    # or in-flight save and its save state (paused by a 409, failed) are the
    # same whether it is showing or not. A design that fetched the form on
    # demand would have to answer what happens to a save whose form has left
    # the document; this one never asks. The cost is markup: a section with
    # many blocks renders all their forms, as a page of that many cards does.
    #
    # The panels are in reading order (`BlockOutline#blocks_in`), which is the
    # order a screen reader meets them in; only one is ever visible, so the
    # order is not a layout.
    #
    # `data-container` is how `admin--blocks` and the stylesheet tell a
    # section's card from a block's without asking for a type by name: the
    # code asks `container?` (`self.draws?`), the markup says the answer.
    #
    # ON A TRANSLATION TAB A SECTION IS NOT THIS CARD but a heading over its
    # blocks' cards (spec §4.5, `SectionGroupComponent`): `self.for` is the
    # one door to both, so the page view and a card streamed in
    # (`Admin::ContentBlocksController#card_for`) cannot draw different things.
    #
    # A SECTION WHOSE TYPE IS GONE (spec §6, `unavailable?`) -- a removed
    # plugin's container, say -- is no `container?` any more and still holds
    # its blocks' rows; `self.draws?` asks the rows too, so it is still drawn
    # here and its blocks do not vanish from the editor. It is the
    # "Unavailable type" card: the danger border, the type's stored name, one
    # sentence, and a section's own two removals as two buttons, under the
    # words the "⋯" menu has for them. "Remove section, keep blocks" comes
    # first and is the safe one: the wrapper nobody can read goes, the texts
    # and pictures in it take its place as cards (`ContentBlocks::Destroy`
    # decides from the rows, so it lifts the blocks of a section whose type
    # is gone as it does any section's); it runs only on a settled screen,
    # for the reason given under THE "⋯" MENU below. "Delete section and its
    # blocks…" opens the section's delete dialog, which says how many blocks
    # go with it. The card must not say "Delete block…" as an unavailable
    # BLOCK's card does: this one holds other blocks, and a person whose
    # plugin was removed would be one press and one confirmation away from
    # deleting a band of content under a label that names one block. The
    # sentence under the header names the ways out and promises nothing the
    # second button undoes. No handle, no settings form and no menu: there
    # is no layout to read a setting from, and a card nobody can read is not
    # moved or copied (as an unavailable block's card is not). Its blocks are
    # listed under it as tiles, in lanes that take nothing
    # (`SectionLanesComponent`), each tile with its form and its own menu: so
    # they can also be opened, edited, deleted, or moved out one by one. A
    # viewer who can't edit sees the card and its tiles and neither button.
    #
    # THE SECTION'S OWN SETTINGS ARE A FORM IN THE HEADER (spec §4.1): layout,
    # background and width, where a block card has its fields in its body. It
    # is an autosave form like a card's, answered by the same action (`Admin
    # ::ContentBlocksController#update`) into the same ids -- the wiring, the
    # base field, the status line and one error slot per setting are all
    # `Admin::EditorScreen::BlockCardComponent`'s, asked of its class, so a section's save
    # is refused as stale (409) and reported exactly as a block's is. Layout
    # is a menu over a hidden input (`SectionLayoutMenuComponent`); the other
    # two are plain selects. A viewer who can't edit sees the three as they
    # are, disabled, in a form with no `admin--autosave` -- as a view-only
    # block card shows its fields.
    #
    # The form holds no other form: the "⋯" menu's Duplicate and Remove are
    # `button_to`s and the dialog's confirm is a form too, so the menu sits
    # after the settings form in the header and the dialog after the body.
    # (A form inside a form is dropped by the HTML parser, and its button
    # would then submit the settings form.)
    #
    # THE "⋯" MENU (spec §4.1), for a viewer who may edit: Move up and Move
    # down are the block card's own buttons (`data-move`, `admin--blocks
    # #moveUp|moveDown`), since a section's card is moved as any card is;
    # `first:` and `last:` are the card's place in the list and say which of
    # the two starts disabled, and `admin--blocks#refreshMoveState` keeps
    # them right afterwards. Duplicate copies the section with its blocks.
    # Then the two deletes, which are the two explicit choices a section's
    # removal is: "Remove section, keep blocks" is sent without a question
    # (`keep_blocks` beside the DELETE) -- the blocks take the section's place
    # as cards -- and "Delete section and its blocks…" opens a dialog that
    # says how many blocks go with it (`SectionDeleteCountComponent`).
    #
    # "REMOVE SECTION, KEEP BLOCKS" RUNS ONLY ON A SETTLED SCREEN
    # (`settled_screen_data`). It is the one action of a section that replaces
    # the forms of blocks that stay: its answer draws a new card for each
    # block in the section's place (`Admin::ContentBlocksController
    # #removal_streams`), and the panels' forms go with the section's card.
    # A row is never lost by it; what a form holds and has not saved would
    # be. So its form carries `admin--queue-hold`, as the editor
    # header's actions do: the press first waits until the write queue is
    # EMPTY (`drained()` -- an edit inside its debounce is sent, and so is one
    # typed while the block's save was on the wire, whose follow-up the
    # removal would otherwise go ahead of, since a held Turbo request waits
    # only for its turn), and it does not run at all when a form ended
    # unclean -- paused by a 409, refused as invalid, given up on offline --
    # because that text is on this screen and nowhere else, possibly in a
    # panel that is closed. One sentence in a toast says so. It asks the whole
    # screen, not the section's forms alone: that is the rule the header's
    # actions already follow, and one rule is easier to keep than two.
    # "Delete section and its blocks…" needs none of it: its answer removes
    # the section's card and replaces nothing, so no block that stays has a
    # form in its way, and the text of a block that is deleted goes with it,
    # which the dialog has said.
    #
    # `editable:` as on a block card: handed down by the page view, asked
    # here when left nil.
    class SectionCardComponent < AdminComponent
      def self.lanes_id(section) = "section-#{section.id}-lanes"

      def self.panels_id(section) = "section-#{section.id}-panels"

      def self.summary_id(section) = "section-#{section.id}-summary"

      # The header's "3 columns · 5 blocks", for the card and for a stream
      # that replaces it after an add or a delete: one place, so the two
      # cannot drift (`SectionSummaryComponent`).
      def self.summary(section:, count:) = Admin::EditorScreen::SectionSummaryComponent.new(section: section, count: count)

      def self.delete_count_id(section) = "section-#{section.id}-delete-count"

      # The dialog's "This also deletes the 2 blocks in it.", for the card and
      # for the stream that recounts it, as `summary` above.
      def self.delete_count(section:, count:) = Admin::EditorScreen::SectionDeleteCountComponent.new(section: section, count: count)

      # The layout menu, for the card and for the stream that follows a saved
      # layout (`SectionLayoutMenuComponent`).
      def self.layout_menu(section:) = Admin::EditorScreen::SectionLayoutMenuComponent.new(section: section)

      # Whether a top-level block is drawn as a section: a container, or a
      # block that still holds blocks although its type is no longer a
      # container's (a section whose type is gone, spec §6) -- asked of the
      # rows the outline was built from, never of the type's name. The page
      # view and `Admin::ContentBlocksController#card_for` both ask here, so
      # a card streamed in is the card a page load would draw.
      def self.draws?(block, outline:) = block.container? || outline.blocks_in(block).any?

      # What draws a section on this tab: this card on the default language's,
      # where structure is edited, and the plain group of its blocks' cards
      # on a translation tab (spec §4.5). `options` are the card's own
      # (`first:`, `last:`, `editable:`, `url_options:`); the group takes what
      # it needs of them.
      def self.for(page:, section:, outline:, locale:, **options)
        component = locale.to_s == ::Locales.default ? self : Admin::EditorScreen::SectionGroupComponent
        component.new(page: page, section: section, outline: outline, locale: locale, **options)
      end

      def initialize(page:, section:, outline:, locale:, url_options: {}, first: false, last: false, editable: nil)
        @page = page
        @section = section
        @outline = outline
        @locale = locale
        @url_options = url_options
        @first = first
        @last = last
        @editable = editable
      end

      def dom_id = ActionView::RecordIdentifier.dom_id(section)

      def panels_id = self.class.panels_id(section)

      def body_id = "section-#{section.id}-body"

      def editable? = @editable.nil? ? (@editable = can_edit?(page)) : @editable

      def first? = @first

      def last? = @last

      # The section's type is no longer registered: see the class comment.
      def unavailable? = section.definition.nil?

      # ---- The settings form: every id is the block card's (see the class comment).

      def form_id = "section-#{section.id}-form"

      def form_url = helpers.admin_page_content_block_path(page, section, **url_options)

      def form_data = editable? ? Admin::EditorScreen::BlockCardComponent.autosave_form_data(section) : {}

      def error_prefix = Admin::EditorScreen::BlockCardComponent.error_prefix(section)

      def status_id = Admin::EditorScreen::BlockCardComponent.status_id(section)

      def base_updated_at_id = Admin::EditorScreen::BlockCardComponent.base_updated_at_id(section)

      def base_updated_at_value = section.updated_at.iso8601(6)

      def field_id(name) = "#{error_prefix}-#{name}"

      def error_id(name) = Admin::Ui::FieldComponent.error_id(error_prefix, name)

      # One menu object for the card: it is drawn in the form, and the layout
      # it shows as current is the value of the form's hidden input.
      def layout_menu = @layout_menu ||= self.class.layout_menu(section: section)

      # A setting as the type reads it: its schema's default where the
      # section has stored none (a section just made holds no settings).
      def setting(name) = section.settings_object(locale: ::Locales.default)&.public_send(name).to_s

      def background_options = BlockTypes::Section::BACKGROUNDS.map { |value| [ t(".backgrounds.#{value}"), value ] }

      def width_options = BlockTypes::Section::WIDTHS.map { |value| [ t(".widths.#{value}"), value ] }

      # `.cs-select` without the full width `setup_select_class` gives it on
      # a form's own line: these two stand side by side in a header.
      def select_class = "cs-select py-1 text-sm"

      # ---- The "⋯" menu and its dialog.

      def duplicate_path = helpers.duplicate_admin_page_content_block_path(page, section, **url_options)

      def destroy_path = helpers.admin_page_content_block_path(page, section, **url_options)

      def delete_dialog_id = "delete-section-#{section.id}"

      # On the form of "Remove section, keep blocks", in the menu and on the
      # card of a section whose type is gone: see the class comment.
      def settled_screen_data = { controller: "admin--queue-hold", action: "submit->admin--queue-hold#submit" }

      def menu_item_class = Admin::EditorScreen::BlockCardComponent::MENU_ITEM_CLASS

      def blocks = outline.blocks_in(section)

      def lanes
        Admin::EditorScreen::SectionLanesComponent.new(page: page, section: section, outline: outline, locale: locale, url_options: url_options, editable: editable?)
      end

      def panel(block)
        Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: locale, url_options: url_options, editable: editable?, placement: :panel)
      end

      private

      attr_reader :page, :section, :outline, :locale, :url_options
    end
  end
end
