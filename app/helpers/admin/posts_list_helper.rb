module Admin
  # The posts list's "No matches" sentence names what the person chose, in
  # the words the filter form showed them: the segment's name, then each
  # filter's label with its chosen option ("Drafts, Type: Blog, Tag: music,
  # and Translation: Outdated"). A type no longer registered or a tag nobody
  # has still filters the list (to nothing), so it is shown as the address
  # carries it and can be recognised; a translation state the list does not
  # know filters nothing, and the caller hands none over.
  # The labels and options are the toolbar's own keys
  # (`admin.components.posts_screen.toolbar`), so the sentence and the form
  # cannot name a filter differently.
  module PostsListHelper
    TOOLBAR = "admin.components.posts_screen.toolbar".freeze

    # `scope` is `Posts::List#scope_name`; `filters` the toolbar's Hash of
    # String values or nil, `translation` being `Posts::List#translation_name`.
    def posts_filter_summary(scope:, filters:, content_types:)
      parts = []
      parts << t("#{TOOLBAR}.scopes.#{scope}") unless scope == "all"
      if filters[:type].present?
        type = content_types.find { |candidate| candidate.name == filters[:type] }
        parts << posts_filter_part(:type, type ? type.label : filters[:type])
      end
      parts << posts_filter_part(:tag, filters[:tag]) if filters[:tag].present?
      parts << posts_filter_part(:translation, t("#{TOOLBAR}.translations.#{filters[:translation]}")) if filters[:translation].present?
      parts << t("admin.posts.index.no_matches.title_contains", text: filters[:q]) if filters[:q].present?
      parts.to_sentence # i18n-ok: to_sentence joins with the locale's support.array words
    end

    private

    def posts_filter_part(name, value) = t("admin.posts.index.no_matches.filter", label: t("#{TOOLBAR}.#{name}"), value: value)
  end
end
