# One post's or one tag's neighbourhood (mind graph canvas spec §3.3). The
# graph is walked as it is drawn: posts and tags are nodes, a `PostRelation`
# joins two posts and a tag joins the posts carrying it. Each depth level
# takes one step outward:
#
#   from a post: its related posts and its tags are depth 1;
#                their related posts, their tags' posts and so on are depth 2.
#   from a tag:  the posts carrying it are depth 1;
#                their related posts and their other tags are depth 2.
#
# Only readable posts are ever stepped onto (`readable`), so an unreadable or
# trashed post is neither a node nor a bridge to what lies behind it. A tag
# reached by the walk becomes a node by `Builder`'s rule: at least two
# READABLE posts carry it (its `count`), and one of them is drawn. The focused
# tag is always a node.
#
# Capped like the global view: a tag on thousands of posts is its own
# explosion. Over the cap the focus is kept first, then nearer posts before
# farther ones, and among equals the better connected.
#
# Cost: three queries per depth level (the relations touching the frontier,
# the frontier posts' tags, the frontier tags' posts) plus five whatever the
# size -- never one per node.
class PostGraph
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
      @readable = AccessControl.scope(@actor, "posts.read", Post.all).select(:id)
      walk

      post_ids = @posts.keys
      relations = PostRelation.where(post_id: post_ids, related_post_id: post_ids).order(:id).pluck(:post_id, :related_post_id)
      tag_links = PostTag.where(tag_id: @tags.keys, post_id: post_ids).order(:tag_id, :post_id).pluck(:tag_id, :post_id)
      tag_counts = PostTag.where(tag_id: @tags.keys, post_id: @readable).group(:tag_id).count

      kept = cut(post_ids, relations, tag_links)
      graph = Builder.new(locale: @locale, url_for: @url_for)
                     .call(post_ids: kept, relations: relations, tag_links: tag_links, tag_counts: tag_counts,
                           min_tag_edges: 1, keep_tag: (@focus.id if @focus.kind == "tag"))
      graph.merge(total: post_ids.size, shown: kept.size,
                  focus: { kind: @focus.kind, id: @focus.id, node_id: @focus.node_id, title: @focus.title, depth: @depth })
    end

    private

    # `@posts` and `@tags`: id => the depth it was first reached at.
    def walk
      @posts = {}
      @tags = {}
      post_frontier = []
      tag_frontier = []
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

        post_frontier = reached_posts.uniq - @posts.keys
        tag_frontier = reached_tags.uniq - @tags.keys
        post_frontier.each { |id| @posts[id] = level }
        tag_frontier.each { |id| @tags[id] = level }
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
