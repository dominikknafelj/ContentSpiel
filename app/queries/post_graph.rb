# The mind graph's data (design spec §6.1/§6.2, round 3 D27): every readable
# post as a node, every `PostRelation` row as one "related" edge, and every
# tag carried by at least two readable posts as a tag node with one "tag"
# edge to each of those posts. A plain query object rather than a controller
# method, so the data itself is testable (and reusable) without rendering the
# graph screen around it.
#
# Shape: `{ nodes: [{ id, title, type, colour_index, status, url }],
# tags: [{ id: "tag-<id>", name, count }], edges: [{ source, target, kind }] }`.
# There is deliberately NO colour here: a node carries its content type's
# `colour_index` (nil for a type that isn't registered any more) and the
# page draws it from the `--cs-cat-<n>` tokens, so a type looks the same in
# the graph as in `Admin::ContentTypeDotComponent`. `status` is
# `Publishable#status` ("draft" / "scheduled" / "live"), the one predicate
# `Admin::StatusChipComponent` is fed from.
#
# `url_for:` builds each node's click target -- the CS Studio post editor by
# default, through the route helper (`admin_post_path`), never a hand-built
# "/cs-studio/..." string: `ContentSpiel::ADMIN_PATH` is configurable.
# `Admin::MindGraphController` passes its own builder so the editing
# language (`admin_url_options`) rides along the way every other CS Studio
# link keeps it.
#
# `actor:` (access-control design spec §3.3 "Scopes for reading") narrows
# the graph to the posts that actor may read -- nodes *and* edges: a
# relation with an unreadable post at either end is left out, so an edge
# can never point at (and so disclose) a node that isn't there. Tags are the
# same disclosure risk, so they are derived ONLY from the readable posts
# already loaded: a tag node exists only when two or more *readable* posts
# carry it, its `count` is that readable number (never the tag's true total,
# which would tell the viewer how many posts they can't see), and an edge
# goes only to a readable post. Required, with no default, so nothing draws
# the whole graph by forgetting to pass one; a trusted code path (console, a
# test) passes `actor: nil`, which the checker allows everything on a
# trusted channel.
#
# Cost: four queries however many posts and tags there are (the scoped
# posts, the relations, the post/tag join rows, the kept tags' names), and no
# cap on the number of posts -- as before this round. A tag on N readable
# posts is N edges, so a very tag-heavy site draws many lines; the graph is
# already as large as the site's readable post count.
class PostGraph
  # A tag on fewer readable posts than this is no connection and has no node.
  MIN_TAGGED_POSTS = 2

  def self.call(...) = new(...).call

  # `locale:` is the language titles are read in, through `Locales.read`'s
  # own fallback chain -- a post with no title in the editing language
  # still gets a label rather than a blank node.
  def initialize(actor:, locale: Locales.default, url_for: ->(post) { Rails.application.routes.url_helpers.admin_post_path(post) })
    @actor = actor
    @locale = locale
    @url_for = url_for
  end

  def call
    posts = AccessControl.scope(@actor, "posts.read", Post.order(:id)).to_a
    post_ids = posts.map(&:id)
    tags, tag_edges = tags_and_edges(post_ids)
    { nodes: nodes(posts), tags: tags, edges: related_edges(post_ids) + tag_edges }
  end

  private

  def nodes(posts)
    posts.map do |post|
      {
        id: post.id,
        title: Locales.read(post, :title, locale: @locale),
        type: post.content_type,
        colour_index: post.definition&.colour_index,
        status: post.status,
        url: @url_for.call(post)
      }
    end
  end

  # One `PostRelation` row is one edge: rows are stored directionally but
  # read as undirected everywhere (`Post#all_related_posts`), and
  # `PostRelation#not_duplicate_reverse_pair` already keeps the reverse
  # pair from ever existing alongside it -- nothing to de-duplicate here.
  #
  # Both ends must be among the readable `post_ids` -- the ids already
  # loaded for the nodes, not a second scope query per end.
  def related_edges(post_ids)
    PostRelation.where(post_id: post_ids, related_post_id: post_ids).order(:id).pluck(:post_id, :related_post_id).map do |post_id, related_post_id|
      { source: post_id, target: related_post_id, kind: "related" }
    end
  end

  # Grouped in Ruby from one join-table read over the readable post ids, so
  # the count is by construction the readable one. Tags are named by a second
  # query for just the surviving ids.
  def tags_and_edges(post_ids)
    by_tag = PostTag.where(post_id: post_ids).order(:post_id).pluck(:tag_id, :post_id).group_by(&:first)
    shared = by_tag.select { |_tag_id, rows| rows.size >= MIN_TAGGED_POSTS }
    names = Tag.where(id: shared.keys).pluck(:id, :name).to_h

    tags = shared.keys.filter_map { |tag_id| { id: "tag-#{tag_id}", name: names[tag_id], count: shared[tag_id].size } if names.key?(tag_id) }
    tags.sort_by! { |tag| [ tag[:name].to_s.downcase, tag[:id] ] }
    edges = shared.flat_map do |tag_id, rows|
      names.key?(tag_id) ? rows.map { |_, post_id| { source: post_id, target: "tag-#{tag_id}", kind: "tag" } } : []
    end
    [ tags, edges ]
  end
end
