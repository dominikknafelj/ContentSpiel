# Which kinds of node and of line a viewer MAY BE SHOWN (pages in the mind
# graph, spec §2 and §6): the one rule the legend's toggles follow, so that
# a kind that can be drawn has its toggle and its key, and a kind that
# cannot has none (no type the viewer cannot read).
#
# IT IS READ OFF WHAT THE BUILDER CAN ANSWER (`Builder#plan`), by what the
# viewer reads at all:
#
#   a page, a post type's hub, a tree line, a lists line   someone who reads a page
#   a post, a related line, a shared tag's line            someone who reads a post
#   a TAG                                                  EITHER: one two readable posts carry,
#                                                          or one a readable page's list block
#                                                          names, whatever posts carry it
#
# The tag is the case a rule of "tags hang on posts" misses: someone who
# reads pages and no post is shown the tags their pages list, and without a
# toggle for them could not switch them off, and would have no key that
# says what the square is. `kinds_test.rb` holds each row against what
# `Global` and `Local` answer for each combination of rights.
#
# (A hub's faint `brings` line has no kind here: it follows "Lists".)
module PostGraph
  module Kinds
    # In the legend's order (`mind_graph/graph_data.js` repeats both).
    NODES = %i[page post tag type].freeze
    LINES = %i[tree lists related tag].freeze

    # What a kind needs the viewer to read: any one of these.
    NODE_NEEDS = { page: %i[pages], post: %i[posts], tag: %i[pages posts], type: %i[pages] }.freeze
    LINE_NEEDS = { tree: %i[pages], lists: %i[pages], related: %i[posts], tag: %i[posts] }.freeze

    # `pages:` and `posts:` whether the viewer can read one at all.
    def self.shown(pages:, posts:)
      reads = { pages: pages, posts: posts }.select { |_kind, held| held }.keys
      { nodes: NODES.select { |kind| NODE_NEEDS.fetch(kind).intersect?(reads) }, lines: LINES.select { |kind| LINE_NEEDS.fetch(kind).intersect?(reads) } }
    end
  end
end
