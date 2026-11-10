module Admin
  module TranslationScreen
    # The Translations matrix: rows are items that need work in any target
    # language, columns the target languages. Each cell is that language's
    # `StateCellComponent` (a mark and a word) linking to the item's editor in
    # that language (a complete language in an incomplete row still links);
    # the row title links to the first outdated language's editor, else the
    # first missing. The type is the kind's chip and its word
    # (`Admin::Ui::RecordChipComponent`).
    #
    # The WHOLE row opens that language: an empty stretched link in the action
    # cell, `absolute inset-0` against the row (not the sticky title cell,
    # which would make it the containing block), with no tab stop and hidden
    # from a screen reader since the title link is both. The cell links stand
    # over it at `lift`. The row ends on its verb ("Review changes →" when
    # anything is outdated, "Translate →" otherwise), dim at rest and accent
    # while the row is under the pointer or holds the focus.
    #
    # `items` are `Admin::TranslationsController::Item`s, already sorted and
    # already limited to what the viewer may read, so every link here is one
    # they can open. With none, "Everything is translated." inside the card.
    #
    # Layout: one card. Many languages make a wide table, so it scrolls inside
    # `.admin-table-scroll` (the page never scrolls sideways): a box at most
    # the window's height under the top bar, its own stacking context, whose
    # head row sticks to its top and whose Item column sticks at its left. A
    # sticky element inside a scrolling box sticks to that box, never to the
    # window, so the head stays in view as the rows scroll inside the box.
    # The stylesheet orders the layers there: the head's corner over the
    # head, the head and the Item column over the cell links, and the box,
    # its own stacking context, under the shell's top bar. Column headers are
    # `<th scope=col>`, row titles `<th scope=row>`; each cell's link carries
    # an `aria-label` with the item, language and state, so colour (and the
    # glyph) is never the only cue.
    class MatrixComponent < Admin::AdminComponent
      def initialize(items:, locales:)
        @items = items
        @locales = locales.map(&:to_s)
      end

      def row_id(item) = item.type == "settings" ? "translation-item-settings" : "translation-item-#{item.type}-#{item.record.id}"

      def language_name(locale) = ::Locales.name(locale, native: true)

      def type_label(item) = t(".types.#{item.type}")

      def title(item)
        case item.type
        when "settings" then t(".settings_title")
        when "media" then item.record.title.presence || t(".untitled")
        else ::Locales.read(item.record, :title, locale: Translations.primary_locale).presence || t(".untitled")
        end
      end

      # The language the row title and the stretched link open: the first outdated one,
      # else the first missing one.
      def focus_locale(item)
        locales.find { |locale| item.states[locale] == :outdated } || locales.find { |locale| item.states[locale] == :missing } || locales.first
      end

      def action_kind(item) = item.states.values.include?(:outdated) ? :review : :translate

      def action(item) = t(".action.#{action_kind(item)}")

      def open_label(item) = t(".open_label.#{action_kind(item)}", title: title(item))

      def editor_path(item, locale)
        case item.type
        when "page" then helpers.admin_page_path(item.record, locale:)
        when "post" then helpers.admin_post_path(item.record, locale:)
        when "media" then helpers.admin_media_path(selected: item.record.id, locale:)
        when "settings" then helpers.admin_settings_path(locale:)
        end
      end

      def cell_label(item, locale)
        t(".cell_label.#{item.states.fetch(locale)}", title: title(item), language: language_name(locale))
      end

      private

      attr_reader :items, :locales
    end
  end
end
