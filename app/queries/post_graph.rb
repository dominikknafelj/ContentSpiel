# The mind graph's data (mind graph canvas spec §3): the queries behind CS
# Studio's Mind graph screen and its two JSON reads.
#
# - `PostGraph::Global`: every readable page, and the best-connected readable
#   posts up to `CAP`; or where to open instead, when that is too many lines.
# - `PostGraph::Local`: one page's, post's or tag's neighbourhood
#   (`PostGraph::Focus`), to depth 1 or 2.
# - `PostGraph::Rows`: the rows of the list's two filters, each a read of
#   its own: the posts no page lists, and the posts one target of a page
#   brings in beyond the ones its local view draws.
# - `PostGraph::Search`: readable pages, posts and tags by name.
# - `PostGraph::Builder`: the nodes and lines the first two share, in two
#   steps: `plan` (which lines; no statement) and `build`.
# - `PostGraph::Site`: the readable posts and pages, loaded once (pages in
#   the mind graph, spec §1), with `PostGraph::Tree` (the page tree as far as
#   the viewer reads it) and `PostGraph::Listings` (which page lists what).
# - `PostGraph::Kinds`: which kinds of node and of line a viewer may be
#   shown at all, by what they read: the legend's toggles ask it.
#
# WHAT IT COSTS, measured on 2026-10-13 at 204 pages and 2,005 posts (the
# pages spec's "As built" has the table and how each figure was taken): the
# whole graph at most thirteen statements and 0.14 s, of which the rows are
# a tenth and the rest is Ruby building 2,202 nodes and 6,204 lines; the
# answer that says where to open instead six statements and 0.05 s; a local
# view, a search and each of the list's reads under 0.06 s. Every read but
# the search loads the site (`Site`, with `Listings`), so what `Listings`
# costs is paid by each: its header says how that is bounded.
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
#                                  name, then "all-posts" last. `count` is
#                                  the readable posts of that type, and for
#                                  "all-posts" EVERY readable post, those of
#                                  a retired type included: the site's total
#                                  as this viewer reads it (design answer
#                                  H2), not what a block with no filter lists
#   edges[]: { source, target, kind: "related" | "tag" | "tree" | "lists" |
#              "brings" }   tree: child -> parent; lists: page -> tag, type
#                           or all-posts; brings: a page's local view only,
#                           hub -> post (or -> its pill). There a post can
#                           have a brings line AND tag lines (a type block
#                           brings it in and it carries a listed tag) and
#                           related lines: degree = related_count +
#                           tag_count + 1. One a tag brings in has no brings
#                           line.
#   more[]:  { id: "more-<target>", count, page, target }   one pill per
#              target, a page's local view only; no key without one
#
#   rows[]:  a post's node as in `nodes` with no line counted, and in
#              `listed` its `via`, the target that brings it in: the list's
#              two reads (`Rows`), `{ total, rows }`, newest first
#
# plus `total`, `shown` and `isolated` (global) or `focus` (local:
# `{ kind: "page" | "post" | "tag", id, node_id, title, depth }`). The
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
  #
  # `page_ids` IS AN ARRAY OF IDS THE CALLER HAS NARROWED: this knows
  # nothing of rights and answers the address of any page id it is given, so
  # a caller hands it the ids of pages the viewer reads and no other. (A
  # relation would be loaded first, a second statement: hand over ids.)
  def self.paths(page_ids, locale:)
    PublicSite::Paths.current_paths("Page", page_ids.to_a)
                     .transform_values { |paths| paths[locale.to_s] || paths[Locales.default.to_s] }.compact
  end
end
