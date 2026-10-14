# What every view of the mind graph loads once (pages in the mind graph, spec
# §1): the posts and pages THIS viewer may read, and what follows from them
# without another statement.
#
# Everything the graph shows is derived from these rows, so nothing can count
# or name a page or a post outside the scope, or a trashed one, which
# `AccessControl.scope` leaves out. THE ROWS, NOT THE PUBLISHED COPIES (spec
# decision 3): CS Studio is the editors' view, and a line a live page's
# unpublished block adds is drawn, with the page's own mark saying so.
#
# A PAGE'S PARENT IS ASKED OF `tree`, NEVER OF THE RECORD: `pages` are
# records that carry `parent_id` (the tree is built from it), and for a page
# whose parent the viewer cannot read that is an id they must not be told.
# `Tree#parent` answers nil there.
#
# Five statements whatever the size: the readable posts (four columns, never
# a body), their tag links, the readable pages (`PAGE_COLUMNS`), and
# `Listings`' two.
#
# A POST'S ROW IS `[id, content_type, recency, updated_at]`, and `recency`
# is a NUMBER: when it was published, a draft when it was last changed, for
# the order "newest first" and nothing else. The publication time itself
# never leaves `rows_of`: a row that carried it as a place in an array could
# be compared with the clock under any name a block parameter gave it, and
# `test/lib/mind_graph_guards_test.rb`, which refuses every line that NAMES
# the column, would not see it. A node's state is `Publishing::State`'s.
module PostGraph
  class Site
    PAGE_COLUMNS = %i[id title parent_id position published_at unpublished_changes_at].freeze

    attr_reader :readable_posts, :post_rows, :tag_links, :tag_counts, :pages, :tree, :listings

    def self.load(actor:) = new(actor)

    # The rows of these posts (see the header), in one statement.
    def self.rows_of(posts)
      posts.pluck(:id, :content_type, :published_at, :updated_at).map { |id, type, published_at, updated_at| [ id, type, (published_at || updated_at).to_f, updated_at ] }
    end

    def initialize(actor)
      @readable_posts = AccessControl.scope(actor, "posts.read", Post.all)
      @post_rows = self.class.rows_of(@readable_posts)
      @tag_links = PostTag.where(post_id: @readable_posts.select(:id)).order(:tag_id, :post_id).pluck(:tag_id, :post_id)
      @tag_counts = @tag_links.group_by(&:first).transform_values(&:size)
      pages = AccessControl.scope(actor, "pages.read", Page.all).select(*PAGE_COLUMNS).to_a
      @tree = Tree.new(pages.map { |page| [ page.id, page.parent_id, page.position ] })
      @pages = pages.sort_by { |page| @tree.rank(page.id) }
      @by_id = @pages.index_by(&:id)
      @listings = Listings.new(page_ids: @pages.map(&:id), post_rows: @post_rows, tag_links: @tag_links)
    end

    def page(id) = @by_id[id]
    def home = @by_id[@tree.home_id]
    def stamps = @stamps ||= @post_rows.to_h { |id, _type, _recency, updated_at| [ id, updated_at ] }
  end
end
