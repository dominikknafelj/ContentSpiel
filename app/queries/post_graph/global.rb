# The whole site's graph, as far as one screen can draw it (mind graph canvas
# spec §3.3; pages in the mind graph, spec §1): every page the viewer reads,
# with the tree's lines and what each page's list blocks point at, and the
# readable posts that have at least one connection, ranked by how many, the
# best-connected `cap` of them.
#
# - A post's connection is a `PostRelation` (either direction), a tag carried
#   by at least `MIN_TAGGED_POSTS` readable posts, or a tag a readable page
#   lists, however few carry it: that tag is a node (its lists line needs an
#   end), so the post has a line to draw. That is decided BEFORE the cut,
#   among all readable posts: a tag's weight in the ranking doesn't depend on
#   which posts happen to survive it.
# - A LISTS LINE IS NOT A POST'S CONNECTION. A page points at a tag, a post
#   type or "All posts", never at a post, so a post only a page lists is
#   still isolated; a drawn post says whether a page lists it (`listed`).
# - Ties break by newest `updated_at`, then id, so two requests cut the same.
# - A post with no connection is left out (spec §2, decision 6) and counted in
#   `isolated`. `total` is the connected posts, `shown` the ones in `nodes`.
# - The pages are never cut and never ranked: all the viewer reads, in tree
#   order.
#
# TOO MANY LINES TO READ AS ONE PICTURE (pages spec decision 6): when the
# plan holds more than `open_above` lines the answer is `{ open:, edges: }`,
# Home's node id and the number of lines, and no graph: the page opens
# Home's local view instead. Counting costs nothing (`Builder#plan`), so
# that answer is six statements. `everything: true` answers the whole graph
# whatever its size, and so does a site with no Home the viewer reads: there
# is nowhere to open, and an address that would be a 404 is never handed out.
#
# `actor:` is required, as everywhere: nothing draws the whole graph by
# forgetting to pass one. Everything is derived from the site as the viewer
# reads it (`Site`), so nothing here can count or name a post or a page
# outside the scope -- or a trashed one, which `AccessControl.scope` already
# leaves out.
#
# Cost: AT MOST thirteen statements whatever the size (a ceiling: a site
# where no list block names a tag does not ask for the tags blocks name, and
# one with no page, or no post drawn, does not ask for that kind's notes) --
# the site's five (the
# readable posts, their tag links, the readable pages, the list blocks, the
# tags those name), the relations, and the builder's seven (the tags' names;
# the pages' addresses, open notes and pending copies; the posts' open
# notes, pending copies and rows). A viewer who is not an owner costs one
# more, constant: their grants, read once a request.
module PostGraph
  class Global
    def self.call(...) = new(...).call

    def initialize(actor:, url_for:, locale: Locales.default, cap: CAP, everything: false, open_above: OPEN_AROUND_HOME_ABOVE)
      @actor = actor
      @locale = locale
      @url_for = url_for
      @cap = cap
      @everything = everything
      @open_above = open_above
    end

    def call
      site = Site.load(actor: @actor)
      readable = site.readable_posts.select(:id)
      relations = PostRelation.where(post_id: readable, related_post_id: readable).order(:id).pluck(:post_id, :related_post_id)
      listed_tags = site.listings.tag_ids

      # A tag a readable page lists connects the posts that carry it, however
      # few: it is a node (spec §1), so the post has a line to draw.
      weight = Hash.new(0)
      relations.each { |post_id, related_id| weight[post_id] += 1; weight[related_id] += 1 }
      site.tag_links.each { |tag_id, post_id| weight[post_id] += 1 if site.tag_counts[tag_id] >= MIN_TAGGED_POSTS || listed_tags.include?(tag_id) }

      kept = weight.keys.sort_by { |id| [ -weight[id], -site.stamps[id].to_f, id ] }.first(@cap)
      builder = Builder.new(site: site, locale: @locale, url_for: @url_for)
      plan = builder.plan(post_ids: kept, relations: relations, tag_links: site.tag_links, tag_counts: site.tag_counts, min_tag_edges: MIN_TAGGED_POSTS,
                          page_ids: site.pages.map(&:id), lists: site.listings.edges)
      # Too many lines to read as one picture: the page is told where to open
      # instead (Home's local view), and nothing more is read. Without a
      # readable Home there is nowhere to open, and the whole graph it is.
      return { open: PostGraph.node_id(:page, site.home.id), edges: plan.edges.size } if !@everything && site.home && plan.edges.size > @open_above

      # A post that went between the site's read and the nodes' has no node
      # (`Builder#build`); it is not one of the connected posts any more,
      # and not one of those shown.
      graph = builder.build(plan)
      went = kept.size - graph[:nodes].size
      graph.merge(total: weight.size - went, shown: graph[:nodes].size, isolated: site.post_rows.size - weight.size)
    end
  end
end
