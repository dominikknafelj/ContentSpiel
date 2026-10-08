# The part `PostGraph::Global` and `PostGraph::Local` share (mind graph canvas
# spec §3.3): given the posts to draw and what connects them, the
# `{ nodes, tags, edges }` the page draws, each node with its `degree` -- the
# number of edges it has IN THIS RESPONSE, so size and label priority match
# what is on screen.
#
# The callers decide WHICH posts; this decides nothing about access. Every id
# handed in is already readable, and the rules that keep the graph from
# disclosing anything hold here because of what it is given:
# - an edge is made only between two posts in `post_ids`, or from a tag to one;
# - a tag's `count` is `tag_counts[tag_id]`, the number of READABLE posts
#   carrying it -- not the tag's true total, and not the smaller number drawn;
# - a tag is a node only when at least `MIN_TAGGED_POSTS` readable posts carry
#   it AND it has `min_tag_edges` edges here (two in the global view, where a
#   tag with one drawn post connects nothing; one in a local view, where a
#   post's own tags are its neighbours). `keep_tag` is the one exception: a
#   local view's focused tag is always a node.
#
# Two queries: the posts (only the columns a node is made from) and the tags'
# names.
module PostGraph
  class Builder
    COLUMNS = %i[id title content_type published_at].freeze

    def initialize(locale:, url_for:)
      @locale = locale
      @url_for = url_for
    end

    def call(post_ids:, relations:, tag_links:, tag_counts:, min_tag_edges:, keep_tag: nil)
      drawn = post_ids.to_set
      related = relations.select { |post_id, related_id| drawn.include?(post_id) && drawn.include?(related_id) }
      by_tag = tag_links.select { |_tag_id, post_id| drawn.include?(post_id) }.group_by(&:first)
      by_tag.select! do |tag_id, rows|
        tag_id == keep_tag || (tag_counts.fetch(tag_id, 0) >= MIN_TAGGED_POSTS && rows.size >= min_tag_edges)
      end
      names = Tag.where(id: by_tag.keys).pluck(:id, :name).to_h
      by_tag.select! { |tag_id, _rows| names.key?(tag_id) }

      degree = Hash.new(0)
      related.each { |post_id, related_id| degree[post_id] += 1; degree[related_id] += 1 }
      by_tag.each_value { |rows| rows.each { |_tag_id, post_id| degree[post_id] += 1 } }

      {
        nodes: nodes(post_ids, degree),
        tags: by_tag.map { |tag_id, rows| { id: "tag-#{tag_id}", name: names[tag_id], count: tag_counts.fetch(tag_id, rows.size), degree: rows.size } }
                    .sort_by { |tag| [ tag[:name].to_s.downcase, tag[:id] ] },
        edges: related.map { |post_id, related_id| { source: post_id, target: related_id, kind: "related" } } +
               by_tag.flat_map { |tag_id, rows| rows.map { |_tag_id, post_id| { source: post_id, target: "tag-#{tag_id}", kind: "tag" } } }
      }
    end

    private

    def nodes(post_ids, degree)
      Post.where(id: post_ids).select(*COLUMNS).order(:id).map do |post|
        {
          id: post.id,
          title: Locales.read(post, :title, locale: @locale),
          type: post.content_type,
          colour_index: post.definition&.colour_index,
          status: post.status,
          url: @url_for.call(post),
          degree: degree[post.id]
        }
      end
    end
  end
end
