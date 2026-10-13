# One page's, post's or tag's neighbourhood (mind graph canvas spec §3.3;
# pages in the mind graph, spec §7). The graph is walked as it is drawn:
# posts, tags and pages are nodes, a `PostRelation` joins two posts, a tag
# joins the posts carrying it, a tree line joins a page to its parent and a
# lists line a page to what its list blocks point at. Each depth level takes
# one step outward:
#
#   from a post: its related posts and its tags are depth 1;
#                their related posts, their tags' posts, and the pages that
#                list one of its tags, are depth 2.
#   from a tag:  the posts carrying it and the pages that list it are depth 1;
#                their related posts and their other tags, those pages'
#                parents and children and what else they list, are depth 2.
#
# A PAGE HAS ITS OWN RULE (spec §7, "The local view around a page"). Depth 1:
# its parent, its children, and the tags or post type its blocks list. Depth
# 2 adds, besides the posts it lists, one more step along the tree: the
# grandparent, the grandchildren and the siblings (the parent's other
# children), each with its tree line. The posts it lists are the
# `LISTED_IN_VIEW` (20) most recent (by `published_at`, a draft by
# `updated_at`) OF THE PAGE, not of each target, each joined by a faint
# `brings` line to the hub that brings it in (one a tag brings in has its
# tag line and no other), plus a "+N more" pill FOR EACH TARGET that brings
# in more (design answer H1), hanging off its hub or tag the same way and
# counting only what that target brings in: the pills' counts add up to what
# the twenty left out. No line joins the page to a post. A post drawn around
# a page shows the tags the page lists and no other of its own: the view is
# the page's, and a post's own neighbourhood is its own local view.
#
# Only readable posts and pages are ever stepped onto (`Site`'s rows, and
# `readable` for the statements), so an unreadable or trashed post or page is
# neither a node nor a bridge to what lies behind it: a page whose parent
# the viewer cannot read has no parent here (`Tree`). A tag reached by the
# walk becomes a node by `Builder`'s rule: at least two READABLE posts carry
# it (its `count`), and one of them is drawn; a tag a drawn page lists is a
# node whatever its count, and so is the focused tag.
#
# Capped like the global view: a tag on thousands of posts is its own
# explosion. Over the cap the focus is kept first, then nearer posts before
# farther ones, and among equals the better connected. (Around a page no
# more than `LISTED_IN_VIEW` posts are reached, so the cap cuts nothing
# there.) The pages are never cut.
#
# Cost, never one statement per node. AT MOST the global view's thirteen
# (the site's five, the relations among the posts reached, the builder's
# seven), plus three per depth level around a post or a tag (the relations
# touching the frontier, the frontier posts' tags, the frontier tags'
# posts). AROUND A PAGE THE WALK ASKS NOTHING: it is the site's rows. "At
# most", because a statement for no ids is not sent: around a page at depth
# 1 no post is drawn, so the relations and the posts' three are not asked
# for (nine), and at depth 2 it is thirteen; a site where no list block
# names a tag does not ask for the tags blocks name. The tag links and the
# readable counts are the site's, narrowed here in Ruby.
module PostGraph
  class Local
    def self.call(...) = new(...).call

    def initialize(actor:, focus:, url_for:, depth: 1, locale: Locales.default, cap: CAP)
      @actor = actor
      @focus = focus
      @url_for = url_for
      @depth = depth.to_s == "2" ? 2 : 1
      @locale = locale
      @cap = cap
    end

    def call
      @site = Site.load(actor: @actor)
      @readable = @site.readable_posts.select(:id)
      @posts = {}
      @tags = {}
      @pages = {}
      @types = Set.new
      @listed = []
      @more = []
      @focus.kind == "page" ? walk_around_page : walk

      post_ids = @posts.keys
      relations = PostRelation.where(post_id: post_ids, related_post_id: post_ids).order(:id).pluck(:post_id, :related_post_id)
      tag_links = @site.tag_links.select { |tag_id, post_id| @tags.key?(tag_id) && @posts.key?(post_id) }

      kept = cut(post_ids, relations, tag_links)
      lists = @site.listings.edges.select { |page_id, target| @pages.key?(page_id) && reached?(target) }
      builder = Builder.new(site: @site, locale: @locale, url_for: @url_for)
      plan = builder.plan(post_ids: kept, relations: relations, tag_links: tag_links, tag_counts: @site.tag_counts, min_tag_edges: 1,
                          page_ids: @pages.keys, lists: lists, brought: brought(kept),
                          keep_tag: (@focus.id if @focus.kind == "tag"), more: @more)
      builder.build(plan).merge(total: post_ids.size, shown: kept.size,
                                focus: { kind: @focus.kind, id: @focus.id, node_id: @focus.node_id, title: @focus.title, depth: @depth })
    end

    private

    def reached?(target)
      target.start_with?("tag-") ? @tags.key?(target.delete_prefix("tag-").to_i) : @types.include?(target)
    end

    # The hub that brings each drawn post of the page in, for its faint line
    # (third design answers, "Local view lines"): the target of the first
    # list block of the page that lists it. A post a TAG brings in is left
    # out: its tag line to that tag is among the tag links, and is the line.
    def brought(kept)
      drawn = kept.to_set
      @listed.filter_map do |page_id, post_id|
        target = @site.listings.target_of(page_id, post_id)
        [ target, post_id ] if drawn.include?(post_id) && target && !target.start_with?("tag-")
      end
    end

    # A page's own rule (pages spec §7; design answers 4 and F5, and the
    # third answers), from what the site has loaded: no statement. Depth 1:
    # its parent, its children and what its blocks list. Depth 2 adds one
    # more step along the tree (the grandparent, the siblings, the
    # grandchildren) and the newest LISTED_IN_VIEW posts it lists; the
    # others are counted behind "+N more", ONE PILL PER TARGET (design
    # answer H1), each on its own hub or tag with what that target brings
    # in, in the order of the page's targets. No line joins the page to a
    # post: `brought`.
    def walk_around_page
      tree = @site.tree
      id = @focus.id
      # Trashed, or taken out of the viewer's scope, between the request's
      # finding the focus and the site's being loaded: not found, as it
      # would be a moment later.
      raise ActiveRecord::RecordNotFound unless @site.page(id)

      @pages[id] = 0
      near = tree.neighbours(id)
      near.each { |page_id| @pages[page_id] = 1 }
      step_onto_targets(id, 1)
      return if @depth < 2

      (near.flat_map { |page_id| tree.neighbours(page_id) } - @pages.keys).uniq.each { |page_id| @pages[page_id] = 2 }
      listed = @site.listings.posts_of(id)
      listed.first(LISTED_IN_VIEW).each do |post_id|
        @posts[post_id] = 2
        @listed << [ id, post_id ]
      end
      left = @site.listings.left_out(id)
      @more = @site.listings.targets(id).filter_map { |target| { page_id: id, target: target, count: left[target] } if left[target] }
    end

    def step_onto_targets(page_id, level)
      @site.listings.targets(page_id).each do |target|
        if target.start_with?("tag-") then @tags[target.delete_prefix("tag-").to_i] ||= level
        else @types << target
        end
      end
    end

    # `@posts`, `@tags` and `@pages`: id => the depth it was first reached at.
    def walk
      post_frontier = []
      tag_frontier = []
      page_frontier = []
      if @focus.kind == "post"
        @posts[@focus.id] = 0
        post_frontier = [ @focus.id ]
      else
        @tags[@focus.id] = 0
        tag_frontier = [ @focus.id ]
      end

      1.upto(@depth) do |level|
        reached_posts = []
        reached_tags = []
        # No `any?` guards: an empty frontier is a cheap `IN (NULL)` statement, and
        # skipping it would make the statement count depend on the shape.
        touching = PostRelation.where(post_id: post_frontier).or(PostRelation.where(related_post_id: post_frontier))
        reached_posts.concat(touching.where(post_id: @readable, related_post_id: @readable).pluck(:post_id, :related_post_id).flatten)
        reached_tags.concat(PostTag.where(post_id: post_frontier).distinct.pluck(:tag_id))
        reached_posts.concat(PostTag.where(tag_id: tag_frontier, post_id: @readable).distinct.pluck(:post_id))

        # Along the pages' lines, from what the site has loaded (no
        # statement): a tag leads to the pages that list it, a page to its
        # parent and children and to what it lists.
        reached_pages = tag_frontier.flat_map { |tag_id| @site.listings.pages_of(PostGraph.node_id(:tag, tag_id)) }
        before = @tags.keys
        page_frontier.each do |page_id|
          reached_pages.concat(@site.tree.neighbours(page_id))
          step_onto_targets(page_id, level)
        end

        post_frontier = reached_posts.uniq - @posts.keys
        tag_frontier = (reached_tags.uniq - before) | (@tags.keys - before)
        page_frontier = reached_pages.uniq - @pages.keys
        post_frontier.each { |id| @posts[id] = level }
        tag_frontier.each { |id| @tags[id] ||= level }
        page_frontier.each { |id| @pages[id] = level }
      end
    end

    def cut(post_ids, relations, tag_links)
      return post_ids if post_ids.size <= @cap

      weight = Hash.new(0)
      relations.each { |post_id, related_id| weight[post_id] += 1; weight[related_id] += 1 }
      tag_links.each { |_tag_id, post_id| weight[post_id] += 1 }
      post_ids.sort_by { |id| [ @posts[id], -weight[id], id ] }.first(@cap)
    end
  end
end
