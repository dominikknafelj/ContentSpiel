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
  class TreeNodeComponent < AdminComponent
    def initialize(page:, children_by_parent:, selected: nil, locale:, url_options: {}, root: false)
      @page = page
      @children_by_parent = children_by_parent
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

    def path = helpers.admin_page_path(page, **url_options)

    def new_child_path = helpers.new_admin_page_path(parent_id: page.id, **url_options)

    def status = page.status

    private

    attr_reader :page, :children_by_parent, :selected, :locale, :url_options
  end
end
