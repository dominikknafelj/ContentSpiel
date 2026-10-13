# The rows of the list's two filters (pages in the mind graph, spec §3, §7,
# decision 10), each its own read and neither a filter over the drawn nodes:
# a post no page lists is very likely a post with no connection, which the
# global view does not draw.
#
# - `unlisted`: the readable posts NO READABLE PAGE lists. True for the
#   viewer, not for the site: someone who reads part of the tree is told a
#   post is unlisted when a page they cannot read lists it, since saying
#   otherwise would disclose that page (spec, Risks).
# - `listed(page_id, target)`: the posts ONE TARGET of that page brings in
#   beyond the LISTED_IN_VIEW its local view draws: the rows behind that
#   target's "+N more" pill (design answer H1: a pill per target). The
#   caller has found the page through `Focus`, so it is readable; `target`
#   is compared with the page's own targets and nothing else is done with
#   it, so a junk one answers no rows.
#
# Newest first, the first `limit` with the whole `total`. A row is a post's
# node exactly as the graph's data has it (`Builder#post_nodes`), with no
# line counted: the page adds a row that is not drawn to the canvas without
# another request. A row of `unlisted` also says whether its post has no
# connection at all (`unconnected`): such a post is one the whole graph's
# notice counts as not shown (`isolated`), and the page takes it out of that
# count when the row adds it, at the posts' cap too, where a post that is
# not drawn may as well be one the cut left out. A row of `listed` also says which hub brings its post in
# (`via`, `Listings#target_of`): added to the canvas it gets that hub's line
# (third design answers). AT MOST eight statements for `listed`, a ceiling:
# the site's five and the nodes' three; `unlisted` asks one more, the
# relations that touch its rows (nine). A read with no row does not ask for the
# nodes (five), and a site where no list block names a tag does not ask for
# the tags blocks name.
#
# `listed` for a page that is not among the site's rows (trashed, or taken
# out of the viewer's scope, since the caller found it) is not found, as
# `Local` answers for a focus that went meanwhile: never an empty answer
# that reads as "nothing more".
module PostGraph
  class Rows
    def initialize(actor:, url_for:, locale: Locales.default, limit: ROW_LIMIT)
      @actor = actor
      @url_for = url_for
      @locale = locale
      @limit = limit
    end

    def unlisted
      site = Site.load(actor: @actor)
      answer(site, site.listings.unlisted, unconnected: true)
    end

    def listed(page_id, target)
      site = Site.load(actor: @actor)
      raise ActiveRecord::RecordNotFound unless site.page(page_id)

      listings = site.listings
      target = target.to_s
      answer(site, listings.left_out_of(page_id, target), via: ->(_post_id) { target }).merge(filter: listings.filter_of(page_id, target))
    end

    private

    def answer(site, ids, via: nil, unconnected: false)
      shown = ids.first(@limit)
      nodes = Builder.new(site: site, locale: @locale, url_for: @url_for).post_nodes(shown).index_by { |node| node[:id] }
      connected = unconnected ? connected(site, shown) : nil
      rows = shown.filter_map do |id|
        node = nodes[PostGraph.node_id(:post, id)] or next
        node = node.merge(unconnected: !connected.include?(id)) if connected
        via ? node.merge(via: via.call(id)) : node
      end
      { total: ids.size, rows: rows }
    end

    # Which of these posts have a connection as `Global` counts one (its
    # `weight`): a relation to a readable post, either way, a tag at least
    # `MIN_TAGGED_POSTS` readable posts carry, or a tag a readable page
    # lists. The rule is written there and here, and
    # `test/queries/post_graph/rows_test.rb` holds the two to one answer.
    # One statement, the relations that touch these posts; asked only when
    # there is a row.
    def connected(site, ids)
      return Set.new if ids.empty?

      readable = site.readable_posts.select(:id)
      among = PostRelation.where(post_id: readable, related_post_id: readable)
      related = among.where(post_id: ids).or(among.where(related_post_id: ids)).pluck(:post_id, :related_post_id).flatten
      listed_tags = site.listings.tag_ids
      tagged = site.tag_links.filter_map { |tag_id, post_id| post_id if site.tag_counts[tag_id] >= MIN_TAGGED_POSTS || listed_tags.include?(tag_id) }
      related.to_set.merge(tagged)
    end
  end
end
