module Admin
  module PagesScreen
    # One page's row in the page tree, drawn through the shared row
    # (`Admin::Ui::TreeItemComponent`, whose `.admin-tree` block is its whole
    # look): `div#tree-row-<id>`, the title (the editing language, falling
    # back per `Locales.read`) as a link into the content frame, a state mark
    # (`TreeStateMarkComponent`), the translation markers, the
    # `tree.row.markers` slot, the child count, an inline "+" to add a child
    # and a drag handle. The `<li>` around it and the children list below it
    # are `TreeNodeComponent`'s, so a row can be drawn and replaced alone.
    # The row hands the shared row no class: the classes of the tree's parts
    # here are `TreeItemComponent::CLASSES`, and a slot's own utilities draw
    # only that part (the markers' ink).
    #
    # TWO WAYS IN, ONE ROW. `TreeNodeComponent` hands each row its slice of
    # what `TreeComponent` loaded once for the whole tree; `for_page` reads
    # the same slice for one page, which is what a settings save answers with
    # (`Admin::PagesController#tree_row_stream`). The two must draw the same
    # markup (`tree_row_component_test.rb`: "a row alone draws what the row
    # draws in the whole tree"), or a save would change how a row looks.
    # A row has no state of its own in the browser: its place, its children
    # list and the tree's scripts are on the `<li>` and the lists around it,
    # which a row's replacement leaves where they are. The row's id, its
    # link's id and its children list's id are the page's, so a live merge
    # and the tree's own redraws find the same elements again.
    #
    # The column is narrow and a title is what a row is for: the drag handle
    # stands in the step's gutter to the row's left, and it, the "+", the
    # markers and the child count rest out of sight until the row is hovered
    # or holds the focus, or any pointer is coarse; the selected row shows
    # its markers and count at rest, never its handle or "+" (the block's
    # reveal rules). A title that does not fit is cut with an ellipsis and
    # whole in its tooltip; a row never wraps (rows of uneven height make drop
    # targets jump).
    #
    # A parent draws the disclosure, naming its children list
    # (`children_list_id`), open or `folded:` as the node around it is drawn
    # (`TreeNodeComponent#folded?`); `admin--tree--disclosure` answers its
    # press. A row drawn alone (`for_page`) reads the open set from the
    # cookie it is handed, so a save's redrawn row says what the branch
    # under it shows.
    #
    # The homepage (the one page without a parent: `only_one_root_page`) is
    # never moved (`Pages::Move` refuses it), so its row has no handle.
    #
    # Access control: a `context_only` row is a page the viewer can't read,
    # shown only as the path to a readable page below it: its title in meta
    # ink, no link, no status, no actions, no row target and no address. A
    # row under such a page (`parent_context_only`) is the top of the branch
    # the viewer may read and is not moved from there, since its siblings are
    # not all shown and a drop would be ranked against a list that isn't the
    # real one. Elsewhere the "+" needs `pages.create` under this page and the
    # handle `pages.move` on it, each asked of the page's branch, which
    # `AccessControl.preload_branches` put on the page beforehand so the check
    # reads no closure rows.
    #
    # `translation_counts` is this page's `{ locale => { missing:, outdated: } }`
    # (`Translations::StateIndex.counts_for`). A row shows "↻N" for N outdated
    # fields and "○N" for N missing ones, summed over the target languages and
    # hidden at zero: no box, never red; the tooltip names the languages.
    #
    # `loaded` is `Admin::Slots.load("tree.row.markers", ...)` over the rows
    # being drawn: the slot hands each entry its slice for this page. A row's
    # markers are drawn after the translation markers.
    #
    # `public_path` is the page's live address in the editing language
    # (`PageTree.paths`), nil without one; the row carries it for a find that
    # starts with "/".
    class TreeRowComponent < AdminComponent
      ROW = Admin::Ui::TreeItemComponent::CLASSES

      # One page's slice of what the tree loads, read for that page alone:
      # its row's columns afresh (`PageTree.row`: the record handed in may
      # predate the unpublished-changes mark), its branch, its readable
      # children's count, whether its parent is readable, its address, its
      # translation counts and its slot data. A fixed number of statements,
      # however many pages the site or the branch holds.
      #
      # `page` is one the viewer may read (the editor's own record, looked up
      # through the read scope), so its row is never context-only. Its
      # children are counted through the same read scope the tree's
      # visibility uses; read scopes are whole branches, so every child of a
      # readable page is readable and the count is the tree's.
      #
      # `open_cookie` is the raw `cs_tree_open`, read for this page and its
      # ancestors (the branch the preload above put on it, so no statement of
      # its own); the page is on the path when it is an ancestor of
      # `selected`, which the editor's own page never is of itself.
      def self.for_page(page, selected:, locale:, url_options:, open_cookie: nil)
        actor = Current.actor
        page = ::PageTree.row(page) || page
        AccessControl.preload_branches([ page ])
        child_count = ::PageTree.readable_child_count(page, actor: actor)
        parent_context_only = ::PageTree.parent_context_only?(page, actor: actor)
        public_path = ::PageTree.paths([ page.id ], locale: locale)[page.id]
        translation_counts = Translations.target_locales.empty? ? {} : Translations::StateIndex.counts_for([ page ]).fetch(page, {})
        loaded = Admin::Slots.load("tree.row.markers", [ page ], viewer: actor)
        on_path = selected.present? && selected.id != page.id && AccessControl.page_branch_ids(selected).include?(page.id)
        open_set = TreeOpenSet.parse(open_cookie, readable_ids: AccessControl.page_branch_ids(page))
        folded = child_count.positive? && !open_set.open?(page.id, root: page.parent_id.nil?, on_path: on_path)

        new(page:, child_count:, translation_counts:, loaded:, selected:, locale:, url_options:, parent_context_only:, public_path:, folded:)
      end

      def self.dom_id(page) = "tree-row-#{page.id}"

      # The id of `page`'s children list, which its disclosure names.
      def self.children_list_id(page) = "tree-children-#{page.id}"

      def initialize(page:, child_count:, translation_counts:, loaded:, selected:, locale:, url_options:, context_only: false, parent_context_only: false, public_path: nil, folded: false)
        @page = page
        @folded = folded
        @child_count = child_count
        @translation_counts = translation_counts
        @loaded = loaded
        @selected = selected
        @locale = locale
        @url_options = url_options
        @context_only = context_only
        @parent_context_only = parent_context_only
        @public_path = public_path
      end

      # Falls back to "(untitled)" rather than an empty string: a brand new
      # child (created with a title in some other locale, or mid-creation) with
      # nothing to show in the admin's current locale would otherwise render an
      # invisible, unclickable link -- indistinguishable from a rendering bug.
      def title
        ::Locales.read(page, :title, locale: locale).presence || t(".untitled")
      end

      def dom_id = self.class.dom_id(page)

      def children_list_id = self.class.children_list_id(page)

      # The title link's id: Turbo gives the focus back to the element of the
      # same id after a stream answer replaces the tree or the row, and
      # `admin--pages--tree#mark` finds the title by it.
      def link_id = "tree-link-#{page.id}"

      def selected? = page == selected

      # How the translation markers rest: clipped out of sight, never removed,
      # so a screen reader still hears "○2" (the block's reveal rule). The
      # selected row draws them shown, so it says what is left to do on the
      # page you are on; `admin--pages--tree#mark` moves this class with the
      # selection.
      def marker_class = selected? ? nil : ROW[:reveal]

      def root? = page.parent_id.nil?

      def context_only? = @context_only

      def parent? = child_count.positive?

      def folded? = @folded

      # The row's hooks for the tree's script: a selectable row is a `row`
      # target named by its page. A context-only row is neither.
      def row_data = context_only? ? {} : { "admin--pages--tree-target": "row", "page-id": page.id }

      def state_mark = @state_mark ||= Admin::PagesScreen::TreeStateMarkComponent.new(page: page)

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

      attr_reader :page, :child_count, :translation_counts, :loaded, :selected, :locale, :url_options, :public_path
    end
  end
end
