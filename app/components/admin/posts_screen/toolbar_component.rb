module Admin
  module PostsScreen
    # The posts list's filter form: one GET form (`FORM_ID`) that applies as
    # it changes (`admin--ui--auto-submit`, no Filter button;
    # `FilterHelper#filter_form_options`), reloading only the `content`
    # frame. It is drawn `display: contents` and holds two parts, which the
    # list rail places (`.admin-list-rail` in `content-spiel.tailwind.css`):
    # the bar (title search, the segmented control with counts -- "All 128 ·
    # Live 96 · Drafts 20 · Scheduled 12" -- and "Clear", which appears when
    # anything is active) and the filter panel (Type, Tag and Translation,
    # each under a visible label), which stands in the rail beside the list
    # where the list has the room and under the bar where it has not. Both
    # parts are one form, so a change in the panel is the form's `change` and
    # the focus is restored by id after the reload, wherever it was.
    #
    # The segmented control is a radio group (`scope`), so it is one tab stop,
    # arrow keys move it and a screen reader says "3 of 4" -- the visual
    # buttons are the radios' labels, the checked one drawn by `:has(:checked)`.
    # The segments are `Posts::List::SCOPES`, the scopes the list reads. The
    # counts are `Posts::List#counts`: they respect every other filter, but
    # not the scope itself, so "Drafts 20" is what choosing Drafts would list.
    class ToolbarComponent < Admin::AdminComponent
      FORM_ID = "posts-filters".freeze

      # Selected is INVERTED: ink with paper words and count, the system's
      # segmented look; the group around the pills is outlined in the field
      # line. The keyboard's ring is the accent on a pill at rest and PAPER,
      # 4px inside, on the selected one: the accent on dark ink is 1.96:1
      # (`test/lib/admin_contrast_test.rb`).
      SEGMENT_CLASS = "flex cursor-pointer items-center gap-1.5 border-r border-line px-3 py-1.5 text-sm text-dim last:border-r-0 hover:bg-sunken " \
                      "has-[:checked]:bg-ink has-[:checked]:font-semibold has-[:checked]:text-paper has-[:checked]:hover:bg-ink " \
                      "has-[:focus-visible]:outline has-[:focus-visible]:outline-2 has-[:focus-visible]:-outline-offset-2 has-[:focus-visible]:outline-accent " \
                      "has-[:checked]:has-[:focus-visible]:outline-paper has-[:checked]:has-[:focus-visible]:-outline-offset-4".freeze

      # `filters` is a Hash of the active values (`q`, `type`, `tag`,
      # `translation`; blank when unset, and `translation` one of
      # `Posts::List::TRANSLATIONS`), `counts` the four scope numbers.
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

      def form_options = helpers.filter_form_options(path, bar: false).merge(id: FORM_ID)

      def bar_class = Admin::FilterHelper::BAR_CLASS

      def scopes = Posts::List::SCOPES

      # Anything the viewer has set (the scope too: "Clear" goes back to All).
      def active? = scope != "all" || filters.values.any?(&:present?)

      def hidden_locale? = locale != ::Locales.default

      def count_for(name) = counts.fetch(name)

      # The types' labels, and the filter's own name when no registered type
      # has it (a type unregistered since the address was made): the list is
      # then filtered to nothing, and the select says by what, as
      # `tag_options` does, rather than read as "All" over an empty list.
      def type_options
        options = content_types.map { |type| [ type.label, type.name ] }
        wanted = filters[:type]
        wanted.present? && options.none? { |_, name| name == wanted } ? options + [ [ wanted, wanted ] ] : options
      end

      # The tags' names, and the filter's own name when no tag has it (a tag
      # renamed or deleted since the address was made): the list is then
      # filtered to nothing, and the select says by what, so the filter can
      # be seen and cleared rather than read as "Any" over an empty list.
      def tag_options
        names = tags.map(&:name)
        wanted = filters[:tag]
        wanted.present? && !names.include?(wanted) ? names + [ wanted ] : names
      end

      # One per state `Posts::List` filters by.
      def translation_options = Posts::List::TRANSLATIONS.map { |value| [ t(".translations.#{value}"), value ] }

      private

      attr_reader :scope, :counts, :content_types, :tags, :filters, :url_options, :locale
    end
  end
end
