module Admin
  module EditorScreen
    # A section in the page editor's block list (sections spec §4.1–§4.3): a
    # card like any other block's -- it is dragged, moved and collapsed by
    # `admin--blocks` exactly as one -- but framed and tinted, and holding the
    # section's columns as lanes of tiles (`SectionLanesComponent`) instead of
    # a form of its own.
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
    # `first:` and `last:` are the card's place in the list, as on a block
    # card; the section has no menu yet to use them in. `editable:` as on a
    # block card: handed down by the page view, asked here when left nil.
    class SectionCardComponent < AdminComponent
      def self.lanes_id(section) = "section-#{section.id}-lanes"

      def self.panels_id(section) = "section-#{section.id}-panels"

      def self.summary_id(section) = "section-#{section.id}-summary"

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

      def summary_id = self.class.summary_id(section)

      def body_id = "section-#{section.id}-body"

      def editable? = @editable.nil? ? (@editable = can_edit?(page)) : @editable

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
