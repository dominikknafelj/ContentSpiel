module Admin
  module DashboardScreen
    # The dashboard's "Languages behind <primary language>" panel, an
    # information panel: per target language its own name, "12 missing · 1
    # outdated", a 4px progress bar of complete/total and, when there is one,
    # the most recently changed outdated item as a link to its editor in that
    # language. The numbers come from `Dashboard::TranslationNeeds`, i.e. from
    # `Translations::StateIndex.summary` over what the viewer may read; nothing
    # is computed here. Hidden when there is nothing to show: one language
    # enabled, or nothing readable (`entries` is empty).
    #
    # The heading names the site's primary language (`Translations.primary_locale`)
    # in CS Studio's language, never a fixed "English": a site whose primary
    # language is German reads "Languages behind German". Each row's language
    # is named in its own language (`entry.name`).
    #
    # Colours: translation states are never red. The bar is `ok` for what is
    # done on a `line` track; the outdated count reads in `warn-ink`.
    class TranslationPanelComponent < Admin::AdminComponent
      # The bar's width in 5% steps, spelled out so Tailwind's scanner sees
      # every class (and so no inline `style` is needed).
      # `Admin::TranslationScreen::SummaryCardComponent` draws its bar with them too.
      WIDTHS = [ "w-0", "w-[5%]", "w-[10%]", "w-[15%]", "w-[20%]", "w-[25%]", "w-[30%]", "w-[35%]", "w-[40%]", "w-[45%]", "w-[50%]", "w-[55%]", "w-[60%]", "w-[65%]", "w-[70%]", "w-[75%]", "w-[80%]", "w-[85%]", "w-[90%]", "w-[95%]", "w-full" ].freeze

      def initialize(entries:)
        @entries = entries
      end

      def render? = entries.any?

      def title = t(".title", language: ::Locales.name(Translations.primary_locale))

      # The overview needs `pages.read` or `posts.read` (its own gate).
      def link
        return unless can?("pages.read") || can?("posts.read")

        [ helpers.admin_translations_path, t(".overview") ]
      end

      def counts(entry)
        parts = []
        parts << t(".missing", count: entry.missing) if entry.missing.positive?
        parts << t(".outdated", count: entry.outdated) if entry.outdated.positive?
        parts.any? ? parts.join(t(".separator")) : t(".all_translated")
      end

      def percent(entry) = entry.total.zero? ? 0 : (entry.complete * 100.0 / entry.total).round

      def width_class(entry) = WIDTHS[(percent(entry) / 5.0).round]

      def item_title(entry)
        type, record = entry.item
        (type == "media" ? record.title : ::Locales.read(record, :title, locale: Translations.primary_locale)).presence || t(".untitled")
      end

      def item_path(entry)
        type, record = entry.item
        locale = entry.locale
        case type
        when "page" then helpers.admin_page_path(record, locale:)
        when "post" then helpers.admin_post_path(record, locale:)
        else helpers.admin_media_path(selected: record.id, locale:)
        end
      end

      private

      attr_reader :entries
    end
  end
end
