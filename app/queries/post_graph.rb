# The mind graph's data (mind graph canvas spec §3): the queries behind CS
# Studio's Mind graph screen and its two JSON reads.
#
# - `PostGraph::Global`: every readable page, and the best-connected readable
#   posts up to `CAP`; or where to open instead, when that is too many lines.
# - `PostGraph::Local`: one post's or tag's neighbourhood (`PostGraph::Focus`).
# - `PostGraph::Search`: readable posts and tags by name.
# - `PostGraph::Builder`: the nodes and lines the first two share, in two
#   steps: `plan` (which lines; no statement) and `build`.
# - `PostGraph::Site`: the readable posts and pages, loaded once (pages in
#   the mind graph, spec §1), with `PostGraph::Tree` (the page tree as far as
#   the viewer reads it) and `PostGraph::Listings` (which page lists what).
#
# Shape (every `id`, `source`, `target`, `parent` and `page` is a node's id,
# `node_id`'s):
#
#   nodes[]: { id: "post-<id>", title, type, colour_index, status, changes,
#              change_at, listed, url, degree, related_count, tag_count,
#              open_notes }
#   tags[]:  { id: "tag-<id>", name, count, degree }
#   pages[]: { id: "page-<id>", title, path, depth, home, parent, order,
#              status, changes, change_at, url, degree, child_count,
#              listed_count, open_notes }                    in tree order
#   types[]: { id: "type-<name>" | "all-posts", name, label, colour_index,
#              count, degree }     by colour slot, then the retired types by
#                                  name, then "all-posts" last
#   edges[]: { source, target, kind: "related" | "tag" | "tree" | "lists" |
#              "brings" }   tree: child -> parent; lists: page -> tag, type
#                           or all-posts; brings: a page's local view only
#   more[]:  { id: "more-<target>", count, page, target }   one pill per
#              target, a page's local view only; no key without one
#
# plus `total`, `shown` and `isolated` (global) or `focus` (local). The
# global view answers `{ open: "page-<home id>", edges: N }` and nothing
# else when the graph holds too many lines to read (`OPEN_AROUND_HOME_ABOVE`).
#
# There is deliberately NO colour here: a post and a post type carry the
# content type's `colour_index` (nil for a type that isn't registered any
# more, which is how a retired type's hub is told: no key says so twice, and
# "all-posts" has none either) and the page draws from the `--cs-cat-<n>`
# tokens, so a type looks the same in the graph as in
# `Admin::Ui::ContentTypeDotComponent`. `status` ("draft", "scheduled",
# "live") and `changes` (nil, "unpublished", "scheduled": the two looks of a
# live record that `status` does not tell apart) are `Publishing::State`'s,
# together one of its five states; `change_at` is the time a scheduled
# change comes into force, in that state alone. No words: the controller
# adds `change_on`, the day as CS Studio writes it.
#
# Every query takes `actor:` with no default, so nothing draws the whole graph
# by forgetting to pass one, and `url_for:` (called with a `Post` or a `Page`)
# with no default, because a query knows no routes (`test/lib/dependency_direction_test.rb`).
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
