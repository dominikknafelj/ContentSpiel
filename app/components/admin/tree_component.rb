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
  class TreeComponent < AdminComponent
    def initialize(root:, selected: nil, locale:, url_options: {})
      @root = root
      @selected = selected
      @locale = locale
      @url_options = url_options
      @children_by_parent = root ? Page.all.to_a.group_by(&:parent_id) : {}
    end

    private

    attr_reader :root, :selected, :locale, :url_options, :children_by_parent
  end
end
