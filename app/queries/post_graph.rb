# The mind graph's data (mind graph canvas spec §3): the queries behind CS
# Studio's Mind graph screen and its two JSON reads.
#
# - `PostGraph::Global`: the best-connected readable posts, up to `CAP`.
# - `PostGraph::Local`: one post's or tag's neighbourhood (`PostGraph::Focus`).
# - `PostGraph::Search`: readable posts and tags by name.
# - `PostGraph::Builder`: the `{ nodes, tags, edges }` the first two share.
# - `PostGraph::Site`: the readable posts and pages, loaded once (pages in
#   the mind graph, spec §1), with `PostGraph::Tree` (the page tree as far as
#   the viewer reads it) and `PostGraph::Listings` (which page lists what).
#   No view asks them yet.
#
# Shape: `{ nodes: [{ id: "post-<id>", title, type, colour_index, status, url,
# degree }], tags: [{ id: "tag-<id>", name, count, degree }], edges: [{ source,
# target, kind }] (both ends a node's id), total, shown }`, plus `isolated` (global) or `focus` (local). There
# is deliberately NO colour here: a node carries its content type's
# `colour_index` (nil for a type that isn't registered any more) and the page
# draws it from the `--cs-cat-<n>` tokens, so a type looks the same in the
# graph as in `Admin::Ui::ContentTypeDotComponent`. `status` is
# `Publishable#status`.
#
# Every query takes `actor:` with no default, so nothing draws the whole graph
# by forgetting to pass one, and `url_for:` with no default, because a query
# knows no routes (`test/lib/dependency_direction_test.rb`).
module PostGraph
  # A tag on fewer readable posts than this is no connection and has no node.
  MIN_TAGGED_POSTS = 2

  # The most posts one graph draws: beyond it the global view keeps the
  # best-connected, and a local view the nearest. Set from the measurements in
  # the spec's §7.
  CAP = 2_000

  # A node's id in the graph's data and everywhere the page writes one (pages
  # spec, decision 4): its kind and its database id, "post-12", "tag-3",
  # "page-7"; a post type's is its stored name, "type-blog". One rule, so no
  # script asks what type an id has.
  def self.node_id(kind, id) = "#{kind}-#{id}"

  # Above this many lines the screen opens in the local view around Home,
  # with "Show everything" (pages spec, decision 6; the design answer's
  # "about 3,000 visible edges").
  OPEN_AROUND_HOME_ABOVE = 3_000

  # How many of the posts a page lists its local view draws; the rest are
  # behind "+N more" (design answer F4, F5).
  LISTED_IN_VIEW = 20

  # The most rows one of the list's reads answers (`unlisted`, `listed`).
  ROW_LIMIT = 200

  # The one node a list block with no filter points at: no record, so no
  # database id to add. And the kind of a "+N more" pill of a page's local
  # view, ONE PER TARGET (design answer H1): its id is the kind and the
  # target it hangs off, `node_id(MORE, "type-blog")` => "more-type-blog".
  ALL_POSTS = "all-posts"
  MORE = "more"

  # Each page's current address in `locale`, else in the default language:
  # `{ page_id => "/about" }`; a page with an address in neither is not in
  # it. One statement, `PublicSite::Paths.current_paths`' (the stored rows'
  # one read for several records), so the read is written once.
  def self.paths(page_ids, locale:)
    PublicSite::Paths.current_paths("Page", page_ids.to_a)
                     .transform_values { |paths| paths[locale.to_s] || paths[Locales.default.to_s] }.compact
  end
end
