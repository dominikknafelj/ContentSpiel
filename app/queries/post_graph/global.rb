# The whole site's graph, as far as one screen can draw it (mind graph canvas
# spec §3.3): the readable posts that have at least one connection, ranked by
# how many, and the best-connected `cap` of them.
#
# - A connection is a `PostRelation` (either direction) or a tag carried by at
#   least `MIN_TAGGED_POSTS` readable posts. That is decided BEFORE the cut,
#   among all readable posts: a tag's weight in the ranking doesn't depend on
#   which posts happen to survive it.
# - Ties break by newest `updated_at`, then id, so two requests cut the same.
# - A post with no connection is left out (spec §2, decision 6) and counted in
#   `isolated`. `total` is the connected posts, `shown` the ones in `nodes`.
#
# `actor:` is required, as everywhere: nothing draws the whole graph by
# forgetting to pass one. Everything is derived from the readable posts'
# ids, so nothing here can count or name a post outside the scope -- or a
# trashed one, which `AccessControl.scope` already leaves out.
#
# Cost: six queries whatever the size -- the readable ids with their
# timestamps, the relations, the tag links, and the builder's three (the
# posts, the tags' names, the posts' open notes).
module PostGraph
  class Global
    def self.call(...) = new(...).call

    def initialize(actor:, url_for:, locale: Locales.default, cap: CAP)
      @actor = actor
      @locale = locale
      @url_for = url_for
      @cap = cap
    end

    def call
      readable = AccessControl.scope(@actor, "posts.read", Post.all)
      stamps = readable.pluck(:id, :updated_at).to_h
      relations = PostRelation.where(post_id: readable.select(:id), related_post_id: readable.select(:id)).order(:id).pluck(:post_id, :related_post_id)
      tag_links = PostTag.where(post_id: readable.select(:id)).order(:tag_id, :post_id).pluck(:tag_id, :post_id)
      tag_counts = tag_links.group_by(&:first).transform_values(&:size)

      weight = Hash.new(0)
      relations.each { |post_id, related_id| weight[post_id] += 1; weight[related_id] += 1 }
      tag_links.each { |tag_id, post_id| weight[post_id] += 1 if tag_counts[tag_id] >= MIN_TAGGED_POSTS }

      kept = weight.keys.sort_by { |id| [ -weight[id], -stamps[id].to_f, id ] }.first(@cap)
      graph = Builder.new(locale: @locale, url_for: @url_for, viewer: (@actor if @actor.is_a?(User)))
                     .call(post_ids: kept, relations: relations, tag_links: tag_links, tag_counts: tag_counts, min_tag_edges: MIN_TAGGED_POSTS)
      graph.merge(total: weight.size, shown: kept.size, isolated: stamps.size - weight.size)
    end
  end
end
