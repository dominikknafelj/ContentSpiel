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
# another request. A row of `listed` also says which hub brings its post in
# (`via`, `Listings#target_of`): added to the canvas it gets that hub's line
# (third design answers). Eight statements each: the site's five and the
# nodes' three.
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
      answer(site, site.listings.unlisted)
    end

    def listed(page_id, target)
      site = Site.load(actor: @actor)
      listings = site.listings
      target = target.to_s
      answer(site, listings.left_out_of(page_id, target), via: ->(_post_id) { target }).merge(filter: listings.filter_of(page_id, target))
    end

    private

    def answer(site, ids, via: nil)
      shown = ids.first(@limit)
      nodes = Builder.new(site: site, locale: @locale, url_for: @url_for).post_nodes(shown).index_by { |node| node[:id] }
      rows = shown.filter_map do |id|
        node = nodes[PostGraph.node_id(:post, id)] or next
        via ? node.merge(via: via.call(id)) : node
      end
      { total: ids.size, rows: rows }
    end
  end
end
