module Admin
  module PagesScreen
    # The page tree column (cs-studio spec §4.2): one `<turbo-frame id="tree">`
    # wrapping the whole tree, rendered from `root` down through nested
    # `Admin::PagesScreen::TreeNodeComponent`s. Every controller that touches the tree
    # (`Admin::PagesController`, `Admin::TreeController`) renders this exact
    # same component -- on a normal page load via `content_for :tree`, and
    # again inside a Turbo Stream `replace` after a move -- so there is
    # exactly one thing "what the tree looks like right now" can mean. The
    # tree's shape changes only through a move, a create or a trash; a
    # settings save changes one page's row and nothing else, so its answer
    # replaces that row alone (`TreeRowComponent.for_page`, drawing what the
    # row draws here).
    #
    # `root`'s own children (and their descendants) are preloaded here, in one
    # query, rather than left to each node to call its own `#children`:
    # closure_tree's `#children` is a query per node, which would make
    # rendering an N-page tree cost N queries instead of one. That query asks
    # for the visible, kept pages only and for the columns the rows read
    # (`PageTree.rows`, `PageTree::COLUMNS`), so a page the viewer can't see
    # or one in the trash is never loaded at all.
    #
    # Only the pages the actor may see are rendered (access-control design
    # spec §3.3 "The page tree"): the readable ones, plus `context_only`
    # ancestors -- pages they can't read that sit above one they can, shown
    # greyed out, unlinked and without actions so the readable page still has
    # its path to the root. Everything else is left out, titles and all. Each
    # remaining row asks `can?` for its own actions (add a child, move), and
    # `AccessControl.preload_branches` gives every listed page its branch up
    # front, so those checks read no closure rows of their own: the whole
    # tree costs the same handful of queries (the pages, the actor's grants,
    # the readable ids and their ancestors, one branch preload) however many
    # pages it shows.
    #
    # Each readable row's outdated and missing translated fields per target
    # language (handoff §10 B24: "↻N" and "○N", summed over the languages, the
    # tooltip naming them) are worked out here too, once for the whole tree,
    # and handed down like `children_by_parent`. They go through
    # `Translations::StateIndex.counts_for`, the stored `translation_states`
    # rows -- one query for the whole tree, however many pages it shows, and
    # nothing recomputed after an autosave (the save service already
    # refreshed the one page it touched). Only readable pages are counted
    # (the pages handed in are the ones the actor may read), and a context-only
    # row gets none: it shows nothing but its title, so a count could never
    # hint at a page the actor can't open. With no target language (one
    # enabled) there's nothing to mark, so none of that runs.
    #
    # What features mark a row with (the `tree.row.markers` slot) is loaded
    # here once for the whole tree, for the readable rows -- `Admin::Slots.load`
    # calls each entry's loader once with all of them, and the result is handed
    # down like `children_by_parent`. A context-only row draws no markers, so
    # none is loaded for it (`tree_visibility` lists kept pages only).
    #
    # The header (handoff §10 C34) holds "Pages", "+ New page" where the actor
    # may create under Home, and a "⋯" menu with "Create starter pages" while
    # Home is the only kept page -- design spec §6.1: offered only when
    # `StarterContents::Add` would get past its own permission checks, so the
    # button and the refusal can't disagree.
    #
    # `root` is swapped for its copy in the loaded list, so the checks on the
    # homepage's own row use the preload too. With no visible root (no pages,
    # or none the actor may see) there's nothing to hang the tree on, and
    # the empty state shows instead.
    class TreeComponent < AdminComponent
      def initialize(root:, selected: nil, locale:, url_options: {})
        @selected = selected
        @locale = locale
        @url_options = url_options
        @children_by_parent = {}
        @context_only_ids = Set.new
        @translation_counts = {}
        @loaded = {}
        @root_page = root
      end

      # Never drawn into a frame answer: a frame answer keeps only `#content`,
      # and the tree column outside it outlives the navigation, so a tree
      # drawn there would be read and sent for nothing. The tree's own script
      # moves the selection to the page the frame opened
      # (`admin--pages--tree`, "The selected row").
      def render? = !helpers.turbo_frame_request?

      def before_render
        @root = @root_page && load_visible(@root_page) if render?
      end

      private

      attr_reader :root, :selected, :locale, :url_options, :children_by_parent, :context_only_ids, :translation_counts, :loaded

      def load_visible(root)
        visibility = AccessControl.tree_visibility(Current.actor)
        visible_ids = visibility[:readable] | visibility[:context_only]
        pages = AccessControl.preload_branches(::PageTree.rows(visible_ids).to_a)

        @context_only_ids = visibility[:context_only]
        @children_by_parent = pages.group_by(&:parent_id)
        readable = pages.reject { |page| @context_only_ids.include?(page.id) }
        @translation_counts = translation_counts_for(readable)
        # The row markers features register, read once for the readable rows.
        @loaded = Admin::Slots.load("tree.row.markers", readable, viewer: Current.actor)
        pages.find { |page| page.id == root.id }
      end

      def translation_counts_for(pages)
        return {} if Translations.target_locales.empty?

        Translations::StateIndex.counts_for(pages).transform_keys(&:id)
      end

      def can_add_page? = root.present? && can?("pages.create", Page.new(parent: root))

      def new_page_path = helpers.new_admin_page_path(**url_options)

      # "Home and nothing else, counting kept pages": a trashed page does not
      # make the site any less empty. The cheap checks first, since the tree
      # is drawn on every editor visit.
      def offer_starter_pages?
        return @offer_starter_pages if defined?(@offer_starter_pages)

        @offer_starter_pages = Page.kept.count == 1 && !StarterContent.added?(locale: Locales.default) && StarterContents::Add.new.permitted?
      end
    end
  end
end
