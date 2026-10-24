module Admin
  module TranslationScreen
    # The Translations matrix (design pass round 2, Task 18, handoff §4.4):
    # rows are items that need work in any target language, columns the target
    # languages. Each cell is that language's `Ui::TranslationChipComponent`
    # linking to the item's editor in that language (a complete language in an
    # incomplete row still links); the row title links to the first outdated
    # language's editor, else the first missing; the call to action reads
    # "Review changes →" when anything is outdated, "Translate →" otherwise.
    #
    # `items` are `Admin::TranslationsController::Item`s, already sorted and
    # already limited to what the viewer may read, so every link here is one
    # they can open. With none, "Everything is translated." inside the card.
    #
    # Layout: many languages make a wide table, so the card scrolls
    # horizontally inside itself (the page never does) and the item column is
    # sticky and keeps a minimum width. Column headers are `<th scope=col>`,
    # row titles `<th scope=row>`; each cell's link carries an `aria-label`
    # with the item, language and state, so colour (and the glyph) is never the
    # only cue.
    class MatrixComponent < Admin::AdminComponent
      def initialize(items:, locales:)
        @items = items
        @locales = locales.map(&:to_s)
      end

      def row_id(item) = item.type == "settings" ? "translation-item-settings" : "translation-item-#{item.type}-#{item.record.id}"

      def language_name(locale) = ::Locales.name(locale, native: true)

      def type_label(item) = Admin::TranslationsController::TYPES.fetch(item.type).fetch(:short)

      def title(item)
        case item.type
        when "settings" then "Site settings · title, tagline"
        when "media" then item.record.title.presence || "(untitled)"
        else ::Locales.read(item.record, :title, locale: Translations.primary_locale).presence || "(untitled)"
        end
      end

      # The language the row title and the CTA open: the first outdated one,
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
