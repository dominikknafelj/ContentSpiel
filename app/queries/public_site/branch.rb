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
  # THREE STATEMENTS whatever the branch's size: its pages, their stored
  # addresses (`PublicSite::Paths.current_paths`, one of the reads the entry
  # guard allows), their copies. The pages above a page are two more.
  # `test/queries/public_site/branch_test.rb` counts them at 4 pages and
  # at 30.
  class Branch
    # One page of a branch. `current` is the page being shown; `open` is a
    # page the shown one is somewhere below. `path` already carries the
    # language's prefix (and the preview's).
    Node = Data.define(:id, :title, :path, :children, :current, :open) do
      def current? = current

      def open? = open

      def leaf? = children.empty?

      # The branch flattened in reading order: a page, then its subpages,
      # each followed by its own.
      def reading_order = [ self ] + children.flat_map(&:reading_order)
    end

    def initialize(urls:, locale: I18n.locale)
      @urls = urls
      @locale = locale.to_s
    end

    # The branch under and including `top`, to any depth, or nil when `top`
    # itself is not shown (trashed, not published, no address in this
    # language). `current` is the page being shown, if it is in the branch.
    def under(top, current: nil)
      pages = top.self_and_descendants.kept.published.to_a # public: rows (which pages are in a branch, and their order, is the tree's; titles are read from the copies below)
      by_id = pages.index_by(&:id)
      return nil unless by_id.key?(top.id)

      build(by_id.fetch(top.id),
        by_parent: pages.group_by(&:parent_id),
        paths: Paths.current_paths("Page", by_id.keys),
        shown: as_shown(pages).index_by(&:id),
        current_id: current&.id,
        open_ids: ids_above(current, by_id))
    end

    # The pages above `page`, the homepage first, each as the public sees
    # it. Empty for the homepage.
    def above(page)
      as_shown(page.ancestors.kept.published.to_a.reverse) # public: rows (which pages are above is the tree's; as_shown hands back the copies)
    end

    private

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

    def build(page, context)
      path = context[:paths].dig(page.id, @locale) or return nil

      children = context[:by_parent].fetch(page.id, []).sort_by { |child| [ child.position.to_i, child.id ] }
        .filter_map { |child| build(child, context) }
      Node.new(id: page.id, title: Locales.read(context[:shown].fetch(page.id), :title, locale: @locale),
        path: "#{@urls.prefix(@locale)}#{path}", children: children,
        current: page.id == context[:current_id], open: context[:open_ids].include?(page.id))
    end
  end
end
