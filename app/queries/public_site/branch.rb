module PublicSite
  # A branch of the page tree as a public template may draw it (theming spec
  # §7): a sidebar, a section's index, the crumbs above a page, previous and
  # next. It answers data and knows no helper, no view and no theme
  # (`ThemeHelper#page_tree` and its neighbours are the ones a template
  # calls).
  #
  # WHAT THE PUBLIC SEES, AND NOTHING ELSE. Which pages are in a branch and
  # in what order is the rows' to say (the tree is not in a copy): kept and
  # published pages only, the rule of every public listing, and a page with
  # no address in the language shown is left out with everything under it,
  # because there is nowhere to link it. But a TITLE is content, and content
  # of a published page comes from its copy (`Publishing.published_all`),
  # never from its rows: the spike this replaces read the rows, and a
  # sidebar would have shown a title nobody had published. In a preview the
  # rows are what is shown, as for every other reader
  # (`ThemeHelper#published_views`). `test/integration/public_canary_test.rb`
  # asks the site under a theme that draws all of this.
  #
  # A TEMPLATE IS HANDED VALUES, NEVER A RECORD. Everything this class
  # answers is a `Node`: a title, an address and a handful of facts, each
  # read here. A `Page` in a template's hand, even one rebuilt from its
  # copy, answers `.children`, `.parent` and `.content_blocks` from the
  # ROWS, and no guard reads a theme's templates for that walk; a node has
  # nothing to walk (`test/queries/public_site/branch_test.rb`: "a node is a
  # value: it answers what is documented and no way to a record or its
  # rows").
  #
  # THE STATEMENTS, whatever the branch's size: its pages, their stored
  # addresses (`PublicSite::Paths.current_paths`, one of the reads the entry
  # guard allows), their copies; and one before them for the pages above
  # the top, which says how deep the branch sits (none when the top is the
  # homepage). So `under` is FOUR, three for the homepage; `around` is the
  # same four and answers the pages above from them, with none per ancestor
  # (one, the pages above, for the homepage itself). A top handed over as a
  # node is one more, to find its row.
  # `test/queries/public_site/branch_test.rb` counts them at 4 pages and
  # at 30.
  class Branch
    # One page as the public sees it.
    #
    # `id`        the page's id: what tells two nodes apart, and what
    #             `page_tree` takes a top by.
    # `title`, `subtitle`
    #             as published, in the language shown, falling back as the
    #             site does. `subtitle` is nil where the page has none.
    # `slug`      the last part of its address in the language shown ("" for
    #             the homepage): an address is stored, and immediate.
    # `path`      its address, with the language's prefix (and the
    #             preview's).
    # `depth`     how far below the homepage: 0 for it, 1 for a page directly
    #             under it.
    # `children`  the pages directly under it, as nodes, in the tree's order,
    #             frozen (a node is remembered for the render, and what one
    #             partial added would be drawn by the next).
    #             EMPTY FOR A NODE THAT WAS NOT READ AS PART OF A BRANCH: the
    #             homepage among the pages above (its branch is the whole
    #             site) and, in a preview, a page above that the section's
    #             tree does not hold.
    # `current?`  the page being shown.
    # `open?`     the shown page is somewhere below: true for every page
    #             above it (every node of `around`'s `above`), also in the
    #             preview of a draft, which the tree itself does not hold.
    # `leaf?`     no children.
    # `reading_order`
    #             itself, then its subpages, each followed by its own.
    Node = Data.define(:id, :title, :subtitle, :slug, :path, :depth, :children, :current, :open) do
      def current? = current

      def open? = open

      def leaf? = children.empty?

      # The branch flattened in reading order: a page, then its subpages,
      # each followed by its own.
      def reading_order = [ self ] + children.flat_map(&:reading_order)
    end

    # What is around a page: the pages above it, the homepage first, and its
    # section (the branch directly under the homepage that it is in) with
    # the page marked. `section` is nil for the homepage and when the section
    # is not shown.
    Around = Data.define(:above, :section)
    NOWHERE = Around.new(above: [].freeze, section: nil)

    # What a branch can be asked about: a page (a row, or one rebuilt from
    # its copy) or a node. NOT "anything with an id": a post answers `id`
    # too, and its number is some page's.
    def self.in_the_tree?(thing) = thing.is_a?(Page) || thing.is_a?(Node)

    def initialize(urls:, locale: I18n.locale)
      @urls = urls
      @locale = locale.to_s
    end

    # The branch under and including `top`, to any depth, or nil when `top`
    # itself is not shown (nil, trashed, not published, no address in this
    # language). `top` is a page or a node; `current` is the page being
    # shown (a page or a node), if it is in the branch. Anything else is no
    # top and marks nothing (`in_the_tree?`).
    def under(top, current: nil)
      top = row_of(top) or return nil
      current = nil unless self.class.in_the_tree?(current)
      depth = top.root? ? 0 : top.depth # public: rows (how deep the branch sits is the tree's)

      read(top, depth: depth, current: current).first
    end

    # The pages above `page` and its section, from the same statements as
    # the section's tree. `page` is a page or a node; nil, and anything
    # else, is nowhere.
    def around(page)
      page = row_of(page) or return NOWHERE
      chain = page.self_and_ancestors.to_a.reverse # public: rows (which pages are above is the tree's; every title below is read from a copy)
      above = chain[0...-1].each_with_index.select { |row, _| shown?(row) }.to_h
      home, top = chain.first(2)
      section, nodes = read(top, depth: 1, current: page, beside: above) if top && shown?(home) && shown?(top)
      nodes ||= alone(above)

      Around.new(above: above.keys.filter_map { |row| nodes[row.id] }, section: section)
    end

    private

    # A page is itself and a node is looked up; anything else is no page
    # (`in_the_tree?`), and nothing is read for it.
    def row_of(page)
      return page if page.is_a?(Page)
      return nil unless page.is_a?(Node)

      Page.find_by(id: page.id) # public: rows (a node names a page by its id; only its place in the tree is read from the row)
    end

    # Whether the public sees the page, asked of a row in hand: no statement.
    def shown?(row) = row.live? && !row.trashed?

    # The branch under `top` as [its node or nil, { page id => node }]. The
    # second holds a node for each page of `beside` too ({ row => depth }:
    # pages outside the branch that the caller wants as published from the
    # same statements; such a node has no children).
    def read(top, depth:, current:, beside: {})
      pages = top.self_and_descendants.kept.published.to_a # public: rows (which pages are in a branch, and their order, is the tree's; titles are read from the copies below)
      by_id = pages.index_by(&:id)
      # `beside` is the pages above the shown one, so each is open, whether
      # or not the walk from the shown page reaches it: in the preview of a
      # draft the shown page is not among `pages`, and the walk finds none.
      context = facts_of(pages | beside.keys).merge(by_parent: pages.group_by(&:parent_id), current_id: current&.id,
        open_ids: ids_above(current, by_id) | beside.keys.map(&:id), nodes: {})
      tree = build(by_id[top.id], depth, context) if by_id.key?(top.id)
      beside.each { |row, at| context[:nodes][row.id] ||= lone(row, at, context) }

      [ tree, context[:nodes].compact ]
    end

    # The pages above a page that is in no section that is shown: each alone.
    def alone(above)
      return {} if above.empty?

      context = facts_of(above.keys)
      above.to_h { |row, at| [ row.id, lone(row, at, context) ] }.compact
    end

    # Two statements for any number of pages: their stored addresses and
    # their copies.
    def facts_of(pages)
      { paths: Paths.current_paths("Page", pages.map(&:id)), shown: as_shown(pages).index_by(&:id) }
    end

    def as_shown(pages) = @urls.preview? ? pages : Publishing.published_all(pages)

    # The ids of the pages of the branch that `current` is below, walked in
    # memory: no statement.
    def ids_above(current, by_id)
      ids = []
      parent_id = current && by_id[current.id]&.parent_id
      while (page = by_id[parent_id])
        ids << page.id
        parent_id = page.parent_id
      end
      ids
    end

    # THE ORDER IS THE TREE'S OWN: by position, a page without one last (as
    # Postgres sorts a NULL, which is what closure_tree's `order: "position"`
    # gives the menu, the subpage list and CS Studio's tree), then by id.
    def in_tree_order(pages) = pages.sort_by { |page| [ page.position.nil? ? 1 : 0, page.position.to_i, page.id ] }

    def build(page, depth, context)
      return nil unless context[:paths].dig(page.id, @locale)

      children = in_tree_order(context[:by_parent].fetch(page.id, [])).filter_map { |child| build(child, depth + 1, context) }
      context[:nodes][page.id] = node(page, depth, context, children: children,
        current: page.id == context[:current_id], open: context[:open_ids].include?(page.id))
    end

    # A page above the shown one that is in no branch read here.
    def lone(row, depth, context)
      return nil unless context[:paths].dig(row.id, @locale)

      node(row, depth, context, children: [], current: false, open: true)
    end

    def node(page, depth, context, children:, current:, open:)
      shown = context[:shown].fetch(page.id)
      stored = context[:paths].dig(page.id, @locale)
      Node.new(id: page.id, title: Locales.read(shown, :title, locale: @locale), subtitle: Locales.read(shown, :subtitle, locale: @locale),
        slug: stored.split("/").last.to_s, path: @urls.path_from(stored, @locale),
        depth: depth, children: children.freeze, current: current, open: open)
    end
  end
end
