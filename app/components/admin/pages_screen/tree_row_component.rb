module Admin
  module PagesScreen
    # One page's row in the page tree (cs-studio spec §4.2): `div#tree-row-<id>`,
    # the title (admin-locale, falling back per `Locales.read`), a state mark
    # (`TreeStateMarkComponent`), the translation markers, the `tree.row.markers`
    # slot, the child count, an inline "+" to add a child and a drag handle.
    # The `<li>` around it and the children list below it are
    # `TreeNodeComponent`'s, so a row can be drawn and replaced alone.
    #
    # TWO WAYS IN, ONE ROW. `TreeNodeComponent` hands each row its slice of
    # what `TreeComponent` loaded once for the whole tree; `for_page` reads
    # the same slice for one page, which is what a settings save answers with
    # (`Admin::PagesController#tree_row_stream`). The two must draw the same
    # markup (`tree_row_component_test.rb`: "a row alone draws what the row
    # draws in the whole tree"), or a save would change how a row looks.
    # A row has no state of its own in the browser: its place, its children
    # list and the tree's scripts are on the `<li>` and the lists around it,
    # which a row's replacement leaves where they are.
    #
    # The column is narrow and a title is what a row is for (Claude Design,
    # 2026-10-13, T2): the drag handle stands in the 16px indent to the row's
    # left and shows on hover or focus, and so does the child count (the tree
    # does not collapse, so a count at rest would say what is in view anyway).
    # A title that still does not fit is cut with an ellipsis and whole in the
    # link's `title`; a row never wraps (rows of uneven height make drop
    # targets jump).
    #
    # The homepage (the one page without a parent: `only_one_root_page`) is
    # never moved (`Pages::Move` refuses it), so its row has no handle.
    #
    # Access control (design spec §3.3/§5): a `context_only` row is a page the
    # viewer can't read, shown only as the path to a readable page below it:
    # greyed-out text, no link, no status, no actions. A row under such a page
    # (`parent_context_only`) is the top of the branch the viewer may read and
    # is not moved from there, since its siblings are not all shown and a drop
    # would be ranked against a list that isn't the real one. Elsewhere the "+"
    # needs `pages.create` under this page and the handle `pages.move` on it,
    # each asked of the page's branch, which `AccessControl.preload_branches`
    # put on the page beforehand so the check reads no closure rows.
    #
    # `translation_counts` is this page's `{ locale => { missing:, outdated: } }`
    # (`Translations::StateIndex.counts_for`). A row shows "↻N" for N outdated
    # fields and "○N" for N missing ones, summed over the target languages and
    # hidden at zero -- no box, never red; the tooltip names the languages
    # (handoff §10 B24). They rest hidden and show as the child count does
    # (`marker_class`).
    #
    # `loaded` is `Admin::Slots.load("tree.row.markers", ...)` over the rows
    # being drawn: the slot hands each entry its slice for this page. A row's
    # markers are drawn after the translation markers.
    class TreeRowComponent < AdminComponent
      # One page's slice of what the tree loads, read for that page alone:
      # its branch, its readable children's count, whether its parent is
      # readable, its translation counts and its slot data. A fixed number of
      # statements, however many pages the site or the branch holds.
      #
      # `page` is one the viewer may read (the editor's own record, looked up
      # through the read scope), so its row is never context-only. Its
      # children are counted through the same read scope the tree's
      # visibility uses; read scopes are whole branches, so every child of a
      # readable page is readable and the count is the tree's.
      def self.for_page(page, selected:, locale:, url_options:)
        actor = Current.actor
        AccessControl.preload_branches([ page ])
        child_count = ::PageTree.readable_child_count(page, actor: actor)
        parent_context_only = ::PageTree.parent_context_only?(page, actor: actor)
        translation_counts = Translations.target_locales.empty? ? {} : Translations::StateIndex.counts_for([ page ]).fetch(page, {})
        loaded = Admin::Slots.load("tree.row.markers", [ page ], viewer: actor)

        new(page:, child_count:, translation_counts:, loaded:, selected:, locale:, url_options:, parent_context_only:)
      end

      def self.dom_id(page) = "tree-row-#{page.id}"

      def initialize(page:, child_count:, translation_counts:, loaded:, selected:, locale:, url_options:, context_only: false, parent_context_only: false)
        @page = page
        @child_count = child_count
        @translation_counts = translation_counts
        @loaded = loaded
        @selected = selected
        @locale = locale
        @url_options = url_options
        @context_only = context_only
        @parent_context_only = parent_context_only
      end

      # Falls back to "(untitled)" rather than an empty string: a brand new
      # child (created with a title in some other locale, or mid-creation) with
      # nothing to show in the admin's current locale would otherwise render an
      # invisible, unclickable link -- indistinguishable from a rendering bug.
      def title
        ::Locales.read(page, :title, locale: locale).presence || t(".untitled")
      end

      def dom_id = self.class.dom_id(page)

      # The title link's id, by which the focus finds the link again in a
      # tree drawn afresh (`admin--pages--tree#keepFocus`).
      def link_id = "tree-link-#{page.id}"

      def selected? = page == selected

      # The selected row: bold, on the sunken ground, with the 3px accent bar
      # `.admin-tree-row--selected` draws on its left edge (`content-spiel.tailwind.css`;
      # an inset shadow, so the title does not move). It is a selection and not a
      # marker: accent stays the mark of "unread and addressed to you".
      def row_class = selected? ? "admin-tree-row--selected bg-sunken" : nil

      # How the translation markers rest. Hidden visually, never removed:
      # `sr-only` keeps "○2" in the accessibility tree at rest, and the row's
      # hover, the focus within it and a coarse pointer show it (the child
      # count's classes). On the selected row they are always shown, so it
      # says what is left to do on the page you are on.
      MARKER_AT_REST = "sr-only group-hover/node:not-sr-only group-focus-within/node:not-sr-only any-pointer-coarse:not-sr-only".freeze

      def marker_class = selected? ? "" : MARKER_AT_REST

      def root? = page.parent_id.nil?

      def context_only? = @context_only

      def can_add_child? = !context_only? && can?("pages.create", Page.new(parent: page))

      def movable? = !root? && !context_only? && !@parent_context_only && can?("pages.move", page)

      def path = helpers.admin_page_path(page, **url_options)

      def new_child_path = helpers.new_admin_page_path(parent_id: page.id, **url_options)

      def child_count_label = t(".subpages", count: child_count)

      # :outdated / :missing -> the number of such fields over every target
      # language; always 0 for a context-only row (it shows nothing but its title).
      def translation_total(kind) = (@translation_totals ||= {})[kind] ||= translation_breakdown(kind).values.sum

      # `{ locale => n }`, only the languages with something to report.
      def translation_breakdown(kind)
        (@translation_breakdowns ||= {})[kind] ||=
          if context_only?
            {}
          else
            translation_counts.transform_values { |counts| counts.fetch(kind, 0) }.select { |_code, n| n.positive? }
          end
      end

      # "3 outdated translations: Deutsch, Español" / "1 missing translation: Español"
      # -- the languages are in the label too, so a screen reader gets the same
      # detail the tooltip gives a mouse.
      def translation_label(kind)
        languages = translation_breakdown(kind).keys.map { |code| ::Locales.name(code, native: true) }.join(", ")
        t(".translations.#{kind}.label", count: translation_total(kind), languages: languages)
      end

      # "Deutsch: 2 outdated · Español: 1 outdated"
      def translation_tooltip(kind)
        translation_breakdown(kind).map { |code, n| t(".translations.#{kind}.tooltip", language: ::Locales.name(code, native: true), count: n) }
          .join(t(".translations.separator"))
      end

      private

      attr_reader :page, :child_count, :translation_counts, :loaded, :selected, :locale, :url_options
    end
  end
end
