module Admin
  # The page tree column (cs-studio spec §4.2): one `<turbo-frame id="tree">`
  # wrapping the whole tree, rendered from `root` down through nested
  # `Admin::TreeNodeComponent`s. Every controller that touches the tree
  # (`Admin::PagesController`, `Admin::TreeController`) renders this exact
  # same component -- on a normal page load via `content_for :tree`, and
  # again inside a Turbo Stream `replace` after a move -- so there is
  # exactly one thing "what the tree looks like right now" can mean.
  #
  # `root`'s own children (and their descendants) are preloaded here, in one
  # query, rather than left to each node to call its own `#children`:
  # closure_tree's `#children` is a query per node, which would make
  # rendering an N-page tree cost N queries instead of one.
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
  # Each readable row's translation state per target language (translation
  # helpers spec §4: "a single marker on a page that isn't complete in some
  # language") is worked out here too, once for the whole tree, and handed
  # down like `children_by_parent`. It goes through
  # `Translations::CachedStatus`, not `Translations::Status.for` directly:
  # this tree is re-rendered after every page-settings autosave, and
  # recomputing every page's markers each time made a keystroke pause cost
  # work proportional to the whole site (final fix wave, I1). Cached, it's
  # one light query for the blocks' fingerprints plus one cache read, and
  # only the pages whose content, blocks or confirmations changed since
  # (normally just the one being edited) are worked out again -- with
  # their blocks in one query. Context-only rows get none: they show no
  # status at all, and the actor can't open them. With no target language
  # (one enabled) there's nothing to mark, so none of that runs.
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
      @translation_states = {}
      @root = root && load_visible(root)
    end

    private

    attr_reader :root, :selected, :locale, :url_options, :children_by_parent, :context_only_ids, :translation_states

    def load_visible(root)
      visibility = AccessControl.tree_visibility(Current.actor)
      visible_ids = visibility[:readable] | visibility[:context_only]
      pages = AccessControl.preload_branches(Page.all.to_a.select { |page| visible_ids.include?(page.id) })

      @context_only_ids = visibility[:context_only]
      @children_by_parent = pages.group_by(&:parent_id)
      @translation_states = translation_states_for(pages.reject { |page| @context_only_ids.include?(page.id) })
      pages.find { |page| page.id == root.id }
    end

    def translation_states_for(pages)
      return {} if Translations.target_locales.empty?

      Translations::CachedStatus.for(pages).transform_keys(&:id)
    end
  end
end
