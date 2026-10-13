# The part `PostGraph::Global` and `PostGraph::Local` share (mind graph canvas
# spec §3.3; pages in the mind graph, spec §1, §4): given what to draw and
# what connects it, the `{ nodes, tags, pages, types, edges }` the page
# draws. FIVE KINDS OF NODE: a post (`nodes`), a tag, a page, a post type
# and the one "All posts" node (both in `types`); a page's local view adds
# its "+N more" pills (`more`). Each node carries its `degree`, the number of
# lines it has IN THIS RESPONSE, whatever their kind, so size and label
# priority match what is on screen. A post also carries two halves of that
# number, `related_count` and `tag_count` (its related-post lines and its
# lines to tags that are nodes here): the selection card says "3 related ·
# 2 tags", and the page can't tell the two apart without walking every
# line. In a page's local view a post's `degree` can be one more than the
# two together: the `brings` line from the hub that brings it in.
#
# TWO STEPS. `plan` says WHICH LINES the response holds and asks the
# database nothing, so a caller can count them before a node is built (the
# 3,000-line rule, pages spec decision 6); `build` makes the nodes of a plan.
#
# The callers decide WHICH posts, pages and lists lines; this decides
# nothing about access. Every id handed in is already readable, and the
# rules that keep the graph from disclosing anything hold here because of
# what it is given:
# - a line is made only between two nodes of the response: two posts in
#   `post_ids`, a post and a tag, two pages in `page_ids` (and only to a
#   parent the viewer reads: `Tree#parent`), a drawn page and what its list
#   block points at;
# - a tag's `count` is `tag_counts[tag_id]`, the number of READABLE posts
#   carrying it -- not the tag's true total, and not the smaller number drawn;
# - a tag is a node only when at least `MIN_TAGGED_POSTS` readable posts carry
#   it AND it has `min_tag_edges` lines to posts here (two in the global
#   view, where a tag with one drawn post connects nothing; one in a local
#   view, where a post's own tags are its neighbours). Two exceptions: a tag
#   a drawn page's list block points at is a node whatever its count (the
#   lists line needs its end; the caller handed only readable pages), and
#   `keep_tag`, a local view's focused tag;
# - a post type's `count` and "All posts"' are counted over the site's
#   readable posts: a type's is the readable posts of that stored type,
#   "All posts"' EVERY readable post, a retired type's included (design
#   answer H2: "the site total").
#
# A `brings` line (a hub to a post it brings in, a hub or tag to its "+N
# more") is a page's local view's alone: the whole graph has none, and there
# a type node joins only the pages that list it.
#
# A node's publishing look is `Publishing::State`'s (`status`, and `changes`
# for the two looks of a live record `status` does not tell apart), asked
# with the pending copies read ONCE for all the nodes of a kind, by
# `Publishing.pending`'s own rule; only `state` and `status` are asked, never
# `actions`, which would cost a statement a node. `change_at` is the time a
# scheduled change comes into force and no words: the controller writes the
# day.
#
# A post and a page also carry `open_notes` (notes spec §4.4): the number of
# their open threads, which the page draws as a neutral badge on the node.
# Nothing about the viewer is in it: what is unread for them is said on the
# rows of the node's card, which come from the notes' own endpoint.
#
# `build` costs seven statements whatever the size: the tags' names; the
# pages' addresses, open notes and pending copies; the posts' open notes,
# pending copies and rows (only the columns a node is made from). With no
# page, or with no post, that kind's notes statement is not made
# (`Notes::Counts.by_container` asks nothing for no ids).
module PostGraph
  class Builder
    COLUMNS = %i[id title content_type published_at unpublished_changes_at].freeze
    # The two looks of a live record that the cheap status does not tell
    # apart (spec §4): the rows have moved on, or a change is scheduled.
    CHANGES = { live_with_changes: "unpublished", live_change_scheduled: "scheduled" }.freeze

    Plan = Struct.new(:post_ids, :page_ids, :related, :by_tag, :tag_counts, :lists, :more, :edges, keyword_init: true)

    def initialize(site:, locale:, url_for:, now: Time.current)
      @site = site
      @locale = locale
      @url_for = url_for
      @now = now
    end

    # WHICH LINES the response holds, from what the caller has loaded: no
    # statement. `Global` counts `plan.edges` before any node is built (spec
    # decision 6). The callers decide which posts, pages and lists lines;
    # this decides nothing about access.
    # - `lists`: `[[page_id, target], …]`, already narrowed to the pages
    #   drawn and, in a local view, to the targets the walk reached. A tag a
    #   lists line points at is a node whatever its count.
    # - `brought`: `[[target, post_id], …]`, a page's local view only: the hub
    #   (a post type or "All posts") that brings a drawn post in draws a
    #   faint line to it, so the post does not float loose (third design
    #   answers). The caller leaves out a post a TAG brings in: its "tag"
    #   line to that tag is among `tag_links` already, and two lines between
    #   the same two nodes would be one drawn twice.
    # - `more`: `[{ page_id:, target:, count: }, …]`, ONE "+N more" PILL PER
    #   TARGET (design answer H1), each hanging off its own hub or tag by the
    #   same faint line and counting only what that target brings in.
    # - a tree line needs both pages drawn, and the parent readable (`Tree`).
    def plan(post_ids:, relations:, tag_links:, tag_counts:, min_tag_edges:, page_ids: [], lists: [], brought: [], keep_tag: nil, more: [])
      drawn = post_ids.to_set
      pages = page_ids.to_set
      related = relations.select { |post_id, related_id| drawn.include?(post_id) && drawn.include?(related_id) }
      kept_tags = lists.filter_map { |_page_id, target| target.delete_prefix("tag-").to_i if target.start_with?("tag-") }.to_set
      kept_tags << keep_tag if keep_tag
      by_tag = tag_links.select { |_tag_id, post_id| drawn.include?(post_id) }.group_by(&:first)
      by_tag.select! { |tag_id, rows| kept_tags.include?(tag_id) || (tag_counts.fetch(tag_id, 0) >= MIN_TAGGED_POSTS && rows.size >= min_tag_edges) }
      kept_tags.each { |tag_id| by_tag[tag_id] ||= [] }
      tree = page_ids.filter_map { |id| (parent = @site.tree.parent(id)) && pages.include?(parent) ? [ id, parent ] : nil }

      post = ->(id) { PostGraph.node_id(:post, id) }
      page = ->(id) { PostGraph.node_id(:page, id) }
      edges = related.map { |post_id, related_id| { source: post.call(post_id), target: post.call(related_id), kind: "related" } } +
              by_tag.flat_map { |tag_id, rows| rows.map { |_tag_id, post_id| { source: post.call(post_id), target: PostGraph.node_id(:tag, tag_id), kind: "tag" } } } +
              tree.map { |id, parent| { source: page.call(id), target: page.call(parent), kind: "tree" } } +
              lists.map { |page_id, target| { source: page.call(page_id), target: target, kind: "lists" } } +
              brought.map { |target, post_id| { source: target, target: post.call(post_id), kind: "brings" } } +
              more.map { |pill| { source: pill[:target], target: PostGraph.node_id(MORE, pill[:target]), kind: "brings" } }
      Plan.new(post_ids: post_ids, page_ids: page_ids, related: related, by_tag: by_tag, tag_counts: tag_counts, lists: lists, more: more, edges: edges)
    end

    def build(plan)
      names = Tag.where(id: plan.by_tag.keys).pluck(:id, :name).to_h
      # A tag deleted between the two statements: no node, and no line to it.
      gone = (plan.by_tag.keys - names.keys).to_set { |tag_id| PostGraph.node_id(:tag, tag_id) }
      edges = gone.empty? ? plan.edges : plan.edges.reject { |edge| gone.include?(edge[:target]) || gone.include?(edge[:source]) }
      degree = Hash.new(0)
      edges.each { |edge| degree[edge[:source]] += 1; degree[edge[:target]] += 1 }
      related_count = Hash.new(0)
      plan.related.each { |post_id, related_id| related_count[post_id] += 1; related_count[related_id] += 1 }
      tag_count = Hash.new(0)
      plan.by_tag.each { |tag_id, rows| rows.each { |_tag_id, post_id| tag_count[post_id] += 1 } if names.key?(tag_id) }

      graph = {
        nodes: post_nodes(plan.post_ids, degree: degree, related_count: related_count, tag_count: tag_count),
        tags: names.map { |tag_id, name| tag_node(tag_id, name, plan, degree) }.sort_by { |tag| [ tag[:name].to_s.downcase, tag[:id] ] },
        pages: page_nodes(plan.page_ids, degree),
        types: type_nodes(plan.lists, degree),
        edges: edges
      }
      pills = plan.more.reject { |pill| gone.include?(pill[:target]) }
      graph[:more] = pills.map { |pill| { id: PostGraph.node_id(MORE, pill[:target]), count: pill[:count], page: PostGraph.node_id(:page, pill[:page_id]), target: pill[:target] } } if pills.any?
      graph
    end

    # A post's node, for each id handed in (already narrowed by the read
    # scope, which leaves the trash out). Three statements whatever the
    # number: the posts' open threads, their pending copies, and the posts
    # with the columns a node is made from. `PostGraph::Rows` asks for it
    # with no counts: a row that is not drawn has no line yet.
    def post_nodes(post_ids, degree: {}, related_count: {}, tag_count: {})
      notes = Notes::Counts.by_container("Post", post_ids.to_a)
      pending = pending_copies("Post", post_ids)
      Post.where(id: post_ids).select(*COLUMNS).order(:id).map do |post|
        id = PostGraph.node_id(:post, post.id)
        state = Publishing::State.of(post, now: @now, pending_at: pending[post.id])
        {
          id: id,
          title: Locales.read(post, :title, locale: @locale),
          type: post.content_type,
          colour_index: post.definition&.colour_index,
          status: state.status,
          changes: CHANGES[state.state],
          change_at: (pending[post.id] if state.state == :live_change_scheduled),
          listed: @site.listings.listed?(post.id),
          url: @url_for.call(post),
          degree: degree.fetch(id, 0),
          related_count: related_count.fetch(post.id, 0),
          tag_count: tag_count.fetch(post.id, 0),
          open_notes: notes.fetch(post.id, 0)
        }
      end
    end

    private

    def tag_node(tag_id, name, plan, degree)
      id = PostGraph.node_id(:tag, tag_id)
      { id: id, name: name, count: plan.tag_counts.fetch(tag_id, plan.by_tag[tag_id].size), degree: degree.fetch(id, 0) }
    end

    # The pages are the site's own, loaded once; what is read here is their
    # address, their open threads and their pending copies: three statements.
    def page_nodes(page_ids, degree)
      paths = PostGraph.paths(page_ids, locale: @locale)
      notes = Notes::Counts.by_container("Page", page_ids)
      pending = pending_copies("Page", page_ids)
      tree = @site.tree
      page_ids.sort_by { |page_id| tree.rank(page_id) }.map do |page_id|
        record = @site.page(page_id)
        id = PostGraph.node_id(:page, page_id)
        parent = tree.parent(page_id)
        state = Publishing::State.of(record, now: @now, pending_at: pending[page_id])
        {
          id: id,
          title: Locales.read(record, :title, locale: @locale),
          path: paths[page_id],
          depth: tree.depth(page_id),
          home: page_id == tree.home_id,
          parent: parent && PostGraph.node_id(:page, parent),
          order: tree.rank(page_id),
          status: state.status,
          changes: CHANGES[state.state],
          change_at: (pending[page_id] if state.state == :live_change_scheduled),
          url: @url_for.call(record),
          degree: degree.fetch(id, 0),
          child_count: tree.children(page_id).size,
          listed_count: @site.listings.listed_count(page_id),
          open_notes: notes.fetch(page_id, 0)
        }
      end
    end

    # A post type a drawn lists line points at, and the one "All posts"
    # node. No statement: the counts are the site's readable posts. In the
    # order the list shows them (design answer H2): the types by their
    # colour slot (the order in Settings), then the retired ones by name,
    # then "All posts" last.
    def type_nodes(lists, degree)
      targets = lists.map(&:last).uniq.reject { |target| target.start_with?("tag-") }
      place = ->(target) do
        next [ 2, 0, "" ] if target == ALL_POSTS

        slot = ContentTypes.find(target.delete_prefix("type-"))&.colour_index
        slot ? [ 0, slot, target ] : [ 1, 0, target ]
      end
      targets.sort_by(&place).map do |target|
        if target == ALL_POSTS
          { id: ALL_POSTS, name: nil, label: nil, colour_index: nil, count: @site.listings.post_count, degree: degree.fetch(target, 0) }
        else
          name = target.delete_prefix("type-")
          definition = ContentTypes.find(name)
          { id: target, name: name, label: definition&.label || name, colour_index: definition&.colour_index, count: @site.listings.type_count(name), degree: degree.fetch(target, 0) }
        end
      end
    end

    # `{ record_id => live_at }` of the copies waiting for their time: the
    # fifth state, asked once for every node of a kind, and the time a node
    # in that state hands up as `change_at` (the card's chip says the day).
    # `Publishing.pending`'s own rule, for many records at once: the same
    # scope (`Version.pending`, later than `now`) and, were a record ever to
    # have two, the same row (the lowest id, which `first` answers there and
    # the last pair of a hash keeps here). `State` trusts the time it is
    # handed, so nothing else may be handed.
    def pending_copies(type, ids)
      Publishing::Version.pending(@now).where(record_type: type, record_id: ids.to_a).order(id: :desc).pluck(:record_id, :live_at).to_h
    end
  end
end
