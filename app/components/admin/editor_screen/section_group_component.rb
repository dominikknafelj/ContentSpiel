module Admin
  module EditorScreen
    # A section on a translation tab (sections spec §4.5): a plain group -- a
    # heading, then the card of each block it holds, in reading order, column
    # by column (`BlockOutline#blocks_in`). Each card is the block's own form
    # (`Admin::EditorScreen::BlockCardComponent`, `placement: :group`), so every translated
    # field is its pair with the original, autosaved, refused when stale and
    # confirmed as on any card; a view-only viewer gets the same cards
    # disabled, with no autosave (`editable:` is handed down).
    #
    # NOTHING OF THE DEFAULT TAB'S SECTION CARD'S STRUCTURE IS HERE: no lanes,
    # no tiles, no hidden panels, no settings form. A translator works down
    # the page's text; which column a text stands in is layout, and layout is
    # the same in every language. So the forms are all open, one under the
    # other, in the order the public page is read.
    #
    # ITS SETTINGS ARE READ ONLY. The heading row says the section's settings
    # in the card head's words (`SectionSettingsWordsComponent`, the same
    # component), and each word opens the settings region
    # (`#section-<id>-settings`) through `admin--editor--section#openSettings`,
    # as on the default tab: in place under the heading row below the rail's
    # threshold, and where the rail docks `admin--editor--section-choice`
    # moves that same region into the Section tab and outlines the group
    # (`data-chosen`). The region holds the same words as rows, each under the
    # settings form's own label, then "Same in every language" and a link to
    # the default language's editor with the section chosen (`?section=`). It
    # holds no form and no control: a translation tab never sends a shared
    # value, and a moved region is never a second copy of the default tab's
    # form. A row takes the focus (`tabindex="-1"`) when its word opened the
    # region (`admin--editor--section-settings#focus`). A section whose type
    # is gone has no words and no region, so it is never chosen.
    #
    # THE GROUP STANDS IN THE BLOCK LIST AS THE SECTION'S CARD DOES: a direct
    # child of the list with the section's `dom_id` and `data-block-id`, and a
    # `card` target of `admin--editor--blocks`. The cards around it are still moved
    # from their handles and menus on a translation tab, and the order such a
    # move sends is read from the list's children that carry a
    # `data-block-id` (`admin--editor--blocks#itemsOf`) -- which has to name the
    # section, or the reorder is refused as not listing the page's blocks.
    # It has no handle and no menu of its own, so the section itself is not
    # moved, copied or deleted from this tab: the default-language tab is
    # where structure is edited. `data-container` is the markup's word for
    # "this card holds blocks", as on the section card. The cards inside are
    # the group's children, not the list's, and no `card` targets (`:group`):
    # the list's order never counts them.
    #
    # A section whose type is gone (spec §6) still holds its blocks and they
    # still have translations: it is drawn here like any other, its heading
    # the "Unavailable type" label in place of the name.
    #
    # `first:` and `last:` are the section card's (`SectionCardComponent.for`
    # hands both components the same options); with no Move up or Move down
    # here they say nothing.
    class SectionGroupComponent < AdminComponent
      def initialize(page:, section:, outline:, locale:, url_options: {}, editable: nil, holds: nil, **)
        @page = page
        @section = section
        @outline = outline
        @locale = locale
        @url_options = url_options
        @editable = editable
        @holds = holds
      end

      def dom_id = ActionView::RecordIdentifier.dom_id(section)

      def editable? = @editable.nil? ? (@editable = can_edit?(page)) : @editable

      def unavailable? = section.definition.nil?

      def heading = unavailable? ? t(".unavailable", type: section.block_type) : t(".heading")

      def header_id = "section-#{section.id}-header"

      def settings_id = Admin::EditorScreen::SectionCardComponent.settings_id(section)

      # The words of the heading row: rendered first, so the region's rows,
      # drawn after them, read the same instance's words.
      def words_component = @words_component ||= Admin::EditorScreen::SectionCardComponent.words(section: section)

      # `[setting, label, word]` for the region's rows: what the head words
      # say, each under the settings form's own label.
      def rows
        words_component.words.map { |field, word| [ field, label_for(field), word ] }
      end

      def wrapper_data
        data = { block_id: section.id, container: "", "admin--editor--blocks-target": "card" }
        return data if unavailable?

        data.merge(controller: "admin--editor--section", "admin--editor--section-settings-id-value": settings_id,
          action: "keydown.esc->admin--editor--section#escape admin--editor--section-settings:closed@window->admin--editor--section#settingsClosed")
      end

      def default_language = ::Locales.name(::Locales.default, native: true)

      # The default language's editor with this section chosen. No `locale`:
      # the default language is the editor's own.
      def edit_path = helpers.admin_page_path(page, section: section.id)

      def edit_class = "#{Admin::Ui::ButtonComponent.classes(:tertiary, size: :small)} mt-1 self-start"

      def blocks = outline.blocks_in(section)

      def card(block)
        Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: locale, url_options: url_options, editable: editable?, placement: :group, holds: holds)
      end

      def holds = @holds ||= ::Editing::Holds.on(page, viewer: Current.user, tab: Current.editing_tab)

      private

      attr_reader :page, :section, :outline, :locale, :url_options

      def label_for(field)
        field == "layout" ? t("admin.components.editor_screen.section_layout_menu.label") : t("admin.components.editor_screen.section_card.#{field}")
      end
    end
  end
end
