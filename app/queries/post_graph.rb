# The mind graph's data (mind graph canvas spec §3): the queries behind CS
# Studio's Mind graph screen and its two JSON reads.
#
# - `PostGraph::Global`: the best-connected readable posts, up to `CAP`.
# - `PostGraph::Local`: one post's or tag's neighbourhood (`PostGraph::Focus`).
# - `PostGraph::Search`: readable posts and tags by name.
# - `PostGraph::Builder`: the `{ nodes, tags, edges }` the first two share.
#
# Shape: `{ nodes: [{ id, title, type, colour_index, status, url, degree }],
# tags: [{ id: "tag-<id>", name, count, degree }], edges: [{ source, target,
# kind }], total, shown }`, plus `isolated` (global) or `focus` (local). There
# is deliberately NO colour here: a node carries its content type's
# `colour_index` (nil for a type that isn't registered any more) and the page
# draws it from the `--cs-cat-<n>` tokens, so a type looks the same in the
# graph as in `Admin::ContentTypeDotComponent`. `status` is
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
end
