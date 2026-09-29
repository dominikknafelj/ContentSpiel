require "zlib"

# The mind graph's data (design spec §6.1/§6.2): every post as a node, every
# `PostRelation` row as one edge. A plain query object rather than a
# controller method, so the data itself is testable (and reusable) without
# rendering the graph screen around it.
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
# can never point at (and so disclose) a node that isn't there. Required,
# with no default, so nothing draws the whole graph by forgetting to pass
# one; a trusted code path (console, a test) passes `actor: nil`, which the
# checker allows everything on a trusted channel.
class PostGraph
  # Used for a post whose content type has no colour of its own -- a type
  # registered without `color`, or a stored type that isn't registered any
  # more (`Post#definition` is nil then, the same `find`-not-`fetch`
  # reasoning `Post#definition` itself gives). Picked by a stable hash of
  # the type's name, not by position, so a type keeps its colour from one
  # load to the next however many other types come and go.
  PALETTE = %w[#6366f1 #ec4899 #14b8a6 #f97316 #8b5cf6 #84cc16 #0ea5e9 #e11d48].freeze

  def self.call(...) = new(...).call

  def self.palette_color(content_type)
    PALETTE[Zlib.crc32(content_type.to_s) % PALETTE.size]
  end

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
    { nodes: nodes(posts), edges: edges(posts.map(&:id)) }
  end

  private

  def nodes(posts)
    posts.map do |post|
      {
        id: post.id,
        title: Locales.read(post, :title, locale: @locale),
        content_type: post.content_type,
        color: post.definition&.color.presence || self.class.palette_color(post.content_type),
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
  def edges(post_ids)
    PostRelation.where(post_id: post_ids, related_post_id: post_ids).order(:id).pluck(:post_id, :related_post_id).map do |post_id, related_post_id|
      { source: post_id, target: related_post_id }
    end
  end
end
