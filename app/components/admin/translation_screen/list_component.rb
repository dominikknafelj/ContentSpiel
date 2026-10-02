module Admin
  module TranslationScreen
    # The Translations overview's list (translation helpers spec §4): this
    # page of `Admin::TranslationsController::Item`s, grouped by type in
    # the controller's `TYPES` order, each row its record's title (in the
    # original language -- the translation is what's missing), its state
    # badge for `locale`, and a link to its editor in `locale`. A group
    # with nothing on this page isn't rendered at all; with nothing on the
    # page anywhere, one line saying the language is done.
    class ListComponent < Admin::AdminComponent
      SECTION_IDS = { "page" => "translations-pages", "post" => "translations-posts", "media" => "translations-media" }.freeze

      def initialize(items:, locale:)
        @items = items
        @locale = locale.to_s
      end

      # `[[type, label, items]]`, in `TYPES` order, non-empty groups only.
      def groups
        by_type = items.group_by(&:type)
        Admin::TranslationsController::TYPES.filter_map do |type, config|
          [ type, config[:label], by_type[type] ] if by_type.key?(type)
        end
      end

      def section_id(type) = SECTION_IDS.fetch(type)

      def row_id(item) = "translation-item-#{item.type}-#{item.record.id}"

      def language_name = ::Locales.name(locale, native: true)

      def title(item)
        title = item.type == "media" ? item.record.title : ::Locales.read(item.record, :title, locale: Translations.primary_locale)
        title.presence || "(untitled)"
      end

      def editor_path(item)
        case item.type
        when "page" then helpers.admin_page_path(item.record, locale:)
        when "post" then helpers.admin_post_path(item.record, locale:)
        when "media" then helpers.admin_medium_path(item.record, locale:)
        end
      end

      private

      attr_reader :items, :locale
    end
  end
end
