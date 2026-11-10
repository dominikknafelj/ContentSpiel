module Admin
  module DashboardScreen
    # The dashboard's "Languages behind <primary language>" panel, an
    # information panel: per target language its own name, its progress
    # (`Admin::Ui::LanguageProgressComponent`, the bar and "↻ 1 outdated · 12
    # missing", as the Translations tiles draw it) and, when there is one,
    # the most recently changed outdated item as a link to its editor in that
    # language. The numbers come from `Dashboard::TranslationNeeds`, i.e. from
    # `Translations::StateIndex.summary` over what the viewer may read; nothing
    # is computed here. Hidden when there is nothing to show: one language
    # enabled, or nothing readable (`entries` is empty).
    #
    # The heading names the site's primary language (`Translations.primary_locale`)
    # in its own language, as CS Studio names a language everywhere, never a
    # fixed "English": a site whose primary language is German reads
    # "Languages behind Deutsch". Each row's language is named the same way
    # (`entry.name`).
    class TranslationPanelComponent < Admin::AdminComponent
      def initialize(entries:)
        @entries = entries
      end

      def render? = entries.any?

      def title = t(".title", language: ::Locales.name(Translations.primary_locale, native: true))

      # The overview needs `pages.read` or `posts.read` (its own gate).
      def link
        return unless can?("pages.read") || can?("posts.read")

        [ helpers.admin_translations_path, t(".overview") ]
      end

      def progress(entry)
        Admin::Ui::LanguageProgressComponent.new(language: entry.name, complete: entry.complete, total: entry.total, outdated: entry.outdated, missing: entry.missing)
      end

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
