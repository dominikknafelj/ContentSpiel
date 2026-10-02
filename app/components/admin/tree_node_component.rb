module Admin
  # One page's row within `Admin::TreeComponent` (cs-studio spec §4.2): the
  # title (admin-locale, falling back per `Locales.read`), a status dot,
  # child count, an inline "+" to add a child, a drag handle, and this
  # page's own children rendered the same way -- recursively, so an N-deep
  # branch is just N nested renders of this one component.
  #
  # `children_by_parent` is the *whole* tree's pages grouped by `parent_id`
  # (`Page.all.to_a.group_by(&:parent_id)`), computed once by
  # `Admin::TreeComponent` and threaded through every recursive render --
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
  # the pages the actor may see (`Admin::TreeComponent`), and
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
  # `translation_states` is `{ page_id => { locale => state } }` for the
  # readable rows (`Translations::Status.for`, computed once by
  # `Admin::TreeComponent`, same reasoning as `children_by_parent`); a row
  # not complete in some target language gets one marker naming them.
  class TreeNodeComponent < AdminComponent
    def initialize(page:, children_by_parent:, context_only_ids: Set.new, translation_states: {}, selected: nil, locale:, url_options: {}, root: false)
      @page = page
      @children_by_parent = children_by_parent
      @context_only_ids = context_only_ids
      @translation_states = translation_states
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

    # `{ locale => :missing | :outdated }`, target languages in order; never
    # anything for a context-only row (no status shows there at all).
    def incomplete_locales
      return {} if context_only?

      translation_states.fetch(page.id, {}).reject { |_code, state| state == :complete }
    end

    # "Incomplete in Deutsch (missing), Español (outdated)"
    def translation_marker_label
      "Incomplete in " + incomplete_locales.map { |code, state| "#{::Locales.name(code, native: true)} (#{state})" }.join(", ")
    end

    private

    attr_reader :page, :children_by_parent, :context_only_ids, :translation_states, :selected, :locale, :url_options
  end
end
