module Admin
  module PagesScreen
    # One page's `<li>` within `Admin::PagesScreen::TreeComponent`: its row
    # (`TreeRowComponent`, which a settings save replaces alone), then its
    # own children rendered the same way -- recursively, so an N-deep branch
    # is just N nested renders of this one component. The nesting is this
    # component's, on the tree's own classes (`TreeItemComponent::CLASSES`):
    # the step between levels is never an indent of its own.
    #
    # `children_by_parent` is the tree's visible pages grouped by `parent_id`,
    # computed once by `Admin::PagesScreen::TreeComponent` and threaded through
    # every recursive render -- looking up "this page's children" from that
    # hash is a hash read, not a query, which is what keeps rendering the tree
    # at a fixed number of queries rather than one per node (closure_tree's
    # own `#children` would be the latter). `translation_counts`, `loaded`
    # and `paths` are read once by the tree the same way; each row is handed
    # its slice.
    #
    # The homepage's own `<li>` is never itself inside a Sortable list --
    # only the *children* list nested inside it is a real drop target.
    #
    # Access control: `children_by_parent` holds only the pages the actor may
    # see, and `context_only_ids` the ones among them shown only as the path
    # to a readable page. A context-only page's children list isn't a drop
    # target: every page under a readable one is readable too (read scopes
    # are whole branches), so only a context-only page can have siblings the
    # tree doesn't show, and a drop there would be ranked against a list that
    # isn't the real one. For the same reason a row under a context-only page
    # has no handle (`TreeRowComponent#movable?`).
    class TreeNodeComponent < AdminComponent
      def initialize(page:, children_by_parent:, context_only_ids: Set.new, translation_counts: {}, loaded: {}, paths: {}, selected: nil, locale:, url_options: {})
        @page = page
        @children_by_parent = children_by_parent
        @context_only_ids = context_only_ids
        @translation_counts = translation_counts
        @loaded = loaded
        @paths = paths
        @selected = selected
        @locale = locale
        @url_options = url_options
      end

      # The tree's own order, sorted here because the tree is loaded as one
      # list and not through the association: by position, a page without one
      # last (as Postgres sorts a NULL, which is what closure_tree's
      # `order: "position"` gives the public menu), then by id: the one rule
      # of `TreeOrder`, which a theme's sidebar (`PublicSite::Branch`) asks
      # too. Sorted by the bare column this raised for a row without a
      # position, which the column allows, and the Pages screen was a 500.
      # Never by title, so a retitled page keeps its place and a settings
      # save can redraw its row where it stands.
      def children
        ::TreeOrder.sort(children_by_parent.fetch(page.id, []))
      end

      def child_count = children.size

      def context_only? = context_only_ids.include?(page.id)

      def drop_target? = !context_only?

      private

      attr_reader :page, :children_by_parent, :context_only_ids, :translation_counts, :loaded, :paths, :selected, :locale, :url_options
    end
  end
end
