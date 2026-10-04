module Admin
  module DashboardScreen
    # The dashboard's "Needs translation" card (design pass round 2, Task 16):
    # per target language its own name, "12 missing · 1 outdated", a 4px
    # progress bar of complete/total and, when there is one, the most
    # recently changed outdated item as a link to its editor in that language.
    # The numbers come from `Dashboard::TranslationNeeds`, i.e. from
    # `Translations::StateIndex.summary` over what the viewer may read; nothing
    # is computed here. Hidden when there is nothing to show -- one language
    # enabled, or nothing readable (`entries` is empty).
    #
    # Colours: translation states are never red. The bar is `ok` for what is
    # done on a `line` track; the outdated count reads in `warn-ink`.
    class TranslationCardComponent < Admin::AdminComponent
      # The bar's width in 5% steps, spelled out so Tailwind's scanner sees
      # every class (and so no inline `style` is needed).
      WIDTHS = [ "w-0", "w-[5%]", "w-[10%]", "w-[15%]", "w-[20%]", "w-[25%]", "w-[30%]", "w-[35%]", "w-[40%]", "w-[45%]", "w-[50%]", "w-[55%]", "w-[60%]", "w-[65%]", "w-[70%]", "w-[75%]", "w-[80%]", "w-[85%]", "w-[90%]", "w-[95%]", "w-full" ].freeze

      def initialize(entries:)
        @entries = entries
      end

      def render? = entries.any?

      # The overview needs `pages.read` or `posts.read` (its own gate).
      def link
        return unless can?("pages.read") || can?("posts.read")

        [ helpers.admin_translations_path(locale: entries.first.locale), "Open the translations overview" ]
      end

      def counts(entry)
        parts = []
        parts << "#{entry.missing} missing" if entry.missing.positive?
        parts << "#{entry.outdated} outdated" if entry.outdated.positive?
        parts.any? ? parts.join(" · ") : "All translated"
      end

      def percent(entry) = entry.total.zero? ? 0 : (entry.complete * 100.0 / entry.total).round

      def width_class(entry) = WIDTHS[(percent(entry) / 5.0).round]

      def item_title(entry)
        type, record = entry.item
        (type == "media" ? record.title : ::Locales.read(record, :title, locale: Translations.primary_locale)).presence || "(untitled)"
      end

      def item_path(entry)
        type, record = entry.item
        locale = entry.locale
        case type
        when "page" then helpers.admin_page_path(record, locale:)
        when "post" then helpers.admin_post_path(record, locale:)
        else helpers.admin_medium_path(record, locale:)
        end
      end

      private

      attr_reader :entries
    end
  end
end
