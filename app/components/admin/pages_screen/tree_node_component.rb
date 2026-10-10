module Admin
  module PagesScreen
    # One page's row within `Admin::PagesScreen::TreeComponent` (cs-studio spec §4.2): the
    # title (admin-locale, falling back per `Locales.read`), a status dot,
    # child count, an inline "+" to add a child, a drag handle, and this
    # page's own children rendered the same way -- recursively, so an N-deep
    # branch is just N nested renders of this one component.
    #
    # `children_by_parent` is the *whole* tree's pages grouped by `parent_id`
    # (`Page.all.to_a.group_by(&:parent_id)`), computed once by
    # `Admin::PagesScreen::TreeComponent` and threaded through every recursive render --
    # looking up "this page's children" from that hash is a hash read, not a
    # query, which is what keeps rendering the tree at one query total rather
    # than one per node (closure_tree's own `#children` would be the latter).
    #
    # `root:` marks the homepage: `Pages::Move` refuses to move it at all (it
    # is the one page with nowhere to go -- Page's own `only_one_root_page`
    # validation guarantees exactly one parentless page), so its row has no
    # drag handle, and its own `<li>` is never itself inside a Sortable list --
    # only the *children* list nested inside it is a real drop target.
    #
    # Access control (design spec §3.3/§5): `children_by_parent` holds only
    # the pages the actor may see (`Admin::PagesScreen::TreeComponent`), and
    # `context_only_ids` the ones among them shown only as the path to a
    # readable page. A context-only row is greyed-out text -- no link, no
    # status, no actions -- and its children list isn't a drop target: every
    # page under a readable one is readable too (read scopes are whole
    # branches), so only a context-only page can have siblings the tree
    # doesn't show, and a drop there would be ranked against a list that
    # isn't the real one. Elsewhere the "+" needs `pages.create` under this
    # page and the drag handle `pages.move` on it (the drop target's own
    # `pages.create` is `Pages::Move`'s to check, answered in the tree's
    # status line).
    #
    # `translation_counts` is `{ page_id => { locale => { missing:, outdated: } } }`
    # for the readable rows (`Translations::StateIndex.counts_for`, read once by
    # `Admin::PagesScreen::TreeComponent`, same reasoning as `children_by_parent`). A row
    # shows "↻N" for N outdated fields and "○N" for N missing ones, summed over
    # the target languages and hidden at zero -- no box, never red; the tooltip
    # names the languages (handoff §10 B24).
    #
    # `note_counts` (`{ page_id => open threads on the page and its blocks }`)
    # and `note_unread` (the page ids with something unread for the viewer)
    # come down the same way (`Notes::Counts`, read once by the tree). A row
    # with open notes shows the notes pill after the translation markers --
    # neutral, accent only while something there is unread and addressed to
    # the viewer, nothing at zero (notes spec §4.4, §4.5). It is no link of
    # its own: the row's title opens the page, and its notes are one press on
    # the header's button from there.
    class TreeNodeComponent < AdminComponent
      def initialize(page:, children_by_parent:, context_only_ids: Set.new, translation_counts: {}, note_counts: {}, note_unread: Set.new, selected: nil, locale:, url_options: {}, root: false)
        @page = page
        @children_by_parent = children_by_parent
        @context_only_ids = context_only_ids
        @translation_counts = translation_counts
        @note_counts = note_counts
        @note_unread = note_unread
        @selected = selected
        @locale = locale
        @url_options = url_options
        @root = root
      end

      # Falls back to "(untitled)" rather than an empty string: a brand new
      # child (created with a title in some other locale, or mid-creation) with
      # nothing to show in the admin's current locale would otherwise render an
      # invisible, unclickable link -- indistinguishable from a rendering bug.
      def title
        ::Locales.read(page, :title, locale: locale).presence || "(untitled)"
      end

      def children
        children_by_parent.fetch(page.id, []).sort_by(&:position)
      end

      def child_count = children.size

      def selected? = page == selected

      def root? = @root

      def context_only? = context_only_ids.include?(page.id)

      def drop_target? = !context_only?

      def can_add_child? = !context_only? && can?("pages.create", Page.new(parent: page))

      def movable? = !root? && !context_only? && !context_only_ids.include?(page.parent_id) && can?("pages.move", page)

      def path = helpers.admin_page_path(page, **url_options)

      def new_child_path = helpers.new_admin_page_path(parent_id: page.id, **url_options)

      def status = page.status

      # "outdated" / "missing" -> the number of such fields over every target
      # language; always 0 for a context-only row (it shows nothing but its title).
      def translation_total(kind) = (@translation_totals ||= {})[kind] ||= translation_breakdown(kind).values.sum

      # `{ locale => n }`, only the languages with something to report.
      def translation_breakdown(kind)
        (@translation_breakdowns ||= {})[kind] ||=
          if context_only?
            {}
          else
            translation_counts.fetch(page.id, {}).transform_values { |counts| counts.fetch(kind, 0) }.select { |_code, n| n.positive? }
          end
      end

      # "3 outdated translations: Deutsch, Español" / "1 missing translation: Español"
      # -- the languages are in the label too, so a screen reader gets the same
      # detail the tooltip gives a mouse.
      def translation_label(kind)
        total = translation_total(kind)
        languages = translation_breakdown(kind).keys.map { |code| ::Locales.name(code, native: true) }.join(", ")
        "#{total} #{kind} #{"translation".pluralize(total)}: #{languages}"
      end

      # "Deutsch: 2 outdated · Español: 1 outdated"
      def translation_tooltip(kind)
        translation_breakdown(kind).map { |code, n| "#{::Locales.name(code, native: true)}: #{n} #{kind}" }.join(" · ")
      end

      # Always 0 for a context-only row: the tree reads no count for it.
      def open_notes = note_counts.fetch(page.id, 0)

      def notes_unread? = note_unread.include?(page.id)

      private

      attr_reader :page, :children_by_parent, :context_only_ids, :translation_counts, :note_counts, :note_unread, :selected, :locale, :url_options
    end
  end
end
