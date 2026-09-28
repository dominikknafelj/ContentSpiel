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
  def initialize(locale: Locales.default, url_for: ->(post) { Rails.application.routes.url_helpers.admin_post_path(post) })
    @locale = locale
    @url_for = url_for
  end

  def call
    { nodes: nodes, edges: edges }
  end

  private

  def nodes
    Post.order(:id).map do |post|
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
  def edges
    PostRelation.order(:id).pluck(:post_id, :related_post_id).map do |post_id, related_post_id|
      { source: post_id, target: related_post_id }
    end
  end
end
