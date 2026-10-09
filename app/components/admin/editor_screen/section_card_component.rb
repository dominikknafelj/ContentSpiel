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
    # the lanes sits one `Admin::BlockCardComponent` per block of the section,
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
    # On a translation tab a section is not drawn by this component yet
    # (`self.draws?`): it is the plain block card it was before sections had
    # an editor, until the translation view of the sections plan gives it its
    # own shape (spec §4.5).
    #
    # THE SECTION'S OWN SETTINGS ARE A FORM IN THE HEADER (spec §4.1): layout,
    # background and width, where a block card has its fields in its body. It
    # is an autosave form like a card's, answered by the same action (`Admin
    # ::ContentBlocksController#update`) into the same ids -- the wiring, the
    # base field, the status line and one error slot per setting are all
    # `Admin::BlockCardComponent`'s, asked of its class, so a section's save
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
    # removal is: "Remove section, keep blocks" is sent at once (`keep_blocks`
    # beside the DELETE) -- it loses nothing, the blocks take the section's
    # place as cards -- and "Delete section and its blocks…" opens a dialog
    # that says how many blocks go with it (`SectionDeleteCountComponent`).
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

      # Whether a top-level block is drawn as a section card: a container, on
      # the default language's tab. The page view and `Admin
      # ::ContentBlocksController#card_for` both ask here, so a card streamed
      # in is the card a page load would draw.
      def self.draws?(block, locale:) = block.container? && locale.to_s == ::Locales.default

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

      # ---- The settings form: every id is the block card's (see the class comment).

      def form_id = "section-#{section.id}-form"

      def form_url = helpers.admin_page_content_block_path(page, section, **url_options)

      def form_data = editable? ? Admin::BlockCardComponent.autosave_form_data(section) : {}

      def error_prefix = Admin::BlockCardComponent.error_prefix(section)

      def status_id = Admin::BlockCardComponent.status_id(section)

      def base_updated_at_id = Admin::BlockCardComponent.base_updated_at_id(section)

      def base_updated_at_value = section.updated_at.iso8601(6)

      def field_id(name) = "#{error_prefix}-#{name}"

      def error_id(name) = Admin::FieldComponent.error_id(error_prefix, name)

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

      def menu_item_class = Admin::BlockCardComponent::MENU_ITEM_CLASS

      def blocks = outline.blocks_in(section)

      def lanes
        Admin::EditorScreen::SectionLanesComponent.new(page: page, section: section, outline: outline, locale: locale, url_options: url_options, editable: editable?)
      end

      def panel(block)
        Admin::BlockCardComponent.new(page: page, block: block, locale: locale, url_options: url_options, editable: editable?, placement: :panel)
      end

      private

      attr_reader :page, :section, :outline, :locale, :url_options
    end
  end
end
