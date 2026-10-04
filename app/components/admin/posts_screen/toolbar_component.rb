module Admin
  module PostsScreen
    # The posts list's toolbar (design pass round 2, Task 17, handoff §4.3):
    # title search, a segmented control with counts -- "All 128 · Live 96 ·
    # Drafts 20 · Scheduled 12" -- and Type, Tag and Translation drop-downs.
    # One GET form that applies as it changes (`admin--auto-submit`, no
    # Filter button; `FilterHelper#filter_form_options`), reloading only the
    # `content` frame. "Clear" appears when anything is active.
    #
    # The segmented control is a radio group (`scope`), so it is one tab stop,
    # arrow keys move it and a screen reader says "3 of 4" -- the visual
    # buttons are the radios' labels, the checked one drawn by `:has(:checked)`.
    # The counts are the controller's (`scope_counts`): they respect every
    # other filter, but not the scope itself, so "Drafts 20" is what choosing
    # Drafts would list.
    class ToolbarComponent < Admin::AdminComponent
      SCOPES = [ [ "all", "All" ], [ "live", "Live" ], [ "drafts", "Drafts" ], [ "scheduled", "Scheduled" ] ].freeze
      TRANSLATIONS = [ [ "Needs translation", "needs" ], [ "Outdated", "outdated" ], [ "Complete", "complete" ] ].freeze

      SEGMENT_CLASS = "flex cursor-pointer items-center gap-1.5 border-r border-line px-3 py-1.5 text-sm text-dim last:border-r-0 hover:bg-sunken " \
                      "has-[:checked]:bg-accent-tint has-[:checked]:text-ink has-[:focus-visible]:outline has-[:focus-visible]:outline-2 has-[:focus-visible]:-outline-offset-2 has-[:focus-visible]:outline-accent".freeze

      # `filters` is a Hash of the active values (`q`, `type`, `tag`,
      # `translation`; blank when unset), `counts` the four scope numbers.
      def initialize(scope:, counts:, content_types:, tags:, filters:, url_options: {}, locale: ::Locales.default)
        @scope = scope
        @counts = counts
        @content_types = content_types
        @tags = tags
        @filters = filters
        @url_options = url_options
        @locale = locale.to_s
      end

      def path = helpers.admin_posts_path(**url_options)

      def form_options = helpers.filter_form_options(path)

      # Anything the viewer has set (the scope too: "Clear" goes back to All).
      def active? = scope != "all" || filters.values.any?(&:present?)

      def hidden_locale? = locale != ::Locales.default

      def count_for(name) = counts.fetch(name)

      def type_options = content_types.map { |type| [ type.label, type.name ] }

      private

      attr_reader :scope, :counts, :content_types, :tags, :filters, :url_options, :locale
    end
  end
end
