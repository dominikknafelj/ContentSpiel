require "test_helper"

# `PostGraph::Global` (mind graph canvas spec §3.3): the best-connected
# readable posts up to a cap, their tags and edges, and what was left out.
class PostGraph::GlobalTest < ActiveSupport::TestCase
  def graph(actor: nil, cap: PostGraph::CAP, **options)
    PostGraph::Global.call(actor: actor, cap: cap, url_for: ->(record) { "/cs-studio/#{record.class.name.underscore.pluralize}/#{record.id}" }, **options)
  end

  def relate(a, b) = PostRelation.create!(post: a, related_post: b)
  def pid(post) = "post-#{post.id}"
  def page_id(page) = "page-#{page.id}"

  # A block that names a type nobody registers any more cannot be saved, and
  # exists all the same (it was saved while the type was there): such a name
  # is stored around the validation, as in `listings_test.rb`.
  def list_block(page, **settings)
    stored = settings.stringify_keys
    retired = stored["content_type"].present? && ContentTypes.find(stored["content_type"]).nil?
    block = ContentBlock.create!(owner: page, block_type: :post_list, position: page.content_blocks.count, settings: retired ? stored.except("content_type") : stored)
    block.update_column(:settings, stored) if retired
    block
  end

  test "a connected post is a node with its title, type, colour index, status, url and degree" do
    a = create_post(title: "Alpha", content_type: "resume_entry")
    b = create_post(title: "Beta")
    relate(a, b)

    node = graph[:nodes].find { |n| n[:id] == pid(a) }

    assert_equal({ id: pid(a), title: "Alpha", type: "resume_entry", colour_index: ContentTypes.fetch("resume_entry").colour_index,
                   status: "live", changes: nil, change_at: nil, listed: false, url: "/cs-studio/posts/#{a.id}",
                   degree: 1, related_count: 1, tag_count: 0, open_notes: 0 }, node)
  end

  # The selection card says "N related · N tags": the two halves of `degree`,
  # counted where the edges are made, so the page never has to walk them. A
  # tag that is no node here (one post carries it) is no edge and not counted.
  test "a post carries its related and its tag edges separately, and they add up to its degree" do
    a = create_post(title: "Alpha", tags: %w[shared other lonely])
    b = create_post(title: "Beta", tags: %w[shared other])
    c = create_post(title: "Gamma")
    relate(a, c)
    relate(c, b)

    nodes = graph[:nodes].index_by { |n| n[:id] }

    assert_equal [ 1, 2, 3 ], nodes[pid(a)].values_at(:related_count, :tag_count, :degree)
    assert_equal [ 2, 0, 2 ], nodes[pid(c)].values_at(:related_count, :tag_count, :degree)
    nodes.each_value { |node| assert_equal node[:degree], node[:related_count] + node[:tag_count] }
  end

  test "the url comes from the given builder" do
    a = create_post(title: "A")
    relate(a, create_post(title: "B"))

    result = PostGraph::Global.call(actor: nil, url_for: ->(record) { "/edit/#{record.id}" })

    assert_equal "/edit/#{a.id}", result[:nodes].find { |n| n[:id] == pid(a) }[:url]
    assert result[:nodes].none? { |n| n.key?(:color) || n.key?(:colour) }, "no colour value: the page draws from the --cs-cat tokens"
  end

  test "every id in the data is its kind and its database id: nodes, tags and both ends of every edge" do
    a = create_post(title: "A", tags: [ "shared" ])
    b = create_post(title: "B", tags: [ "shared" ])
    relate(a, b)

    result = graph
    ids = result[:nodes].map { |n| n[:id] } + result[:tags].map { |t| t[:id] }

    assert ids.all? { |id| id.match?(/\A(post|tag)-\d+\z/) }, ids.inspect
    assert_equal ids.sort, result[:edges].flat_map { |e| [ e[:source], e[:target] ] }.uniq.sort
    assert_equal "post-12", PostGraph.node_id("post", 12)
    assert_equal "type-blog", PostGraph.node_id(:type, "blog")
  end

  test "each PostRelation row is exactly one edge" do
    a = create_post(title: "A")
    b = create_post(title: "B")
    relate(a, b)

    assert_equal [ { source: pid(a), target: pid(b), kind: "related" } ], graph[:edges]
  end

  test "a type that isn't registered any more has no colour index" do
    a = create_post(title: "A")
    relate(a, create_post(title: "B"))
    a.update_column(:content_type, "gone/thing")

    node = graph[:nodes].find { |n| n[:id] == pid(a) }

    assert_equal [ "gone/thing", nil ], node.values_at(:type, :colour_index)
  end

  test "status is the post's own: draft, scheduled or live" do
    draft, scheduled, live = %w[Draft Scheduled Live].map { |title| create_post(title: title, tags: [ "t" ]) }
    draft.update_column(:published_at, nil)
    scheduled.update_column(:published_at, 2.days.from_now)
    live.update_column(:published_at, 1.day.ago)

    assert_equal({ pid(draft) => "draft", pid(scheduled) => "scheduled", pid(live) => "live" }, graph[:nodes].to_h { |n| [ n[:id], n[:status] ] })
  end

  test "a post with no connection is left out and counted as isolated" do
    a = create_post(title: "A")
    b = create_post(title: "B")
    create_post(title: "Alone")
    relate(a, b)

    result = graph

    assert_equal [ pid(a), pid(b) ], result[:nodes].map { |n| n[:id] }
    assert_equal 2, result[:total]
    assert_equal 2, result[:shown]
    assert_equal 1, result[:isolated]
  end

  test "a tag on two readable posts is a node, carries the readable count and its degree" do
    a = create_post(title: "A", tags: [ "shared" ])
    b = create_post(title: "B", tags: [ "shared" ])
    create_post(title: "C", tags: [ "lonely" ])
    tag = Tag.find_by!(name: "shared")

    result = graph

    assert_equal [ { id: "tag-#{tag.id}", name: "shared", count: 2, degree: 2 } ], result[:tags]
    assert_equal [ { source: pid(a), target: "tag-#{tag.id}", kind: "tag" }, { source: pid(b), target: "tag-#{tag.id}", kind: "tag" } ], result[:edges]
    assert_equal 1, result[:isolated], "a tag on one post connects nothing"
  end

  test "over the cap the best-connected posts are kept, and total says how many there were" do
    hub = create_post(title: "Hub")
    spokes = 4.times.map { |i| create_post(title: "Spoke #{i}") }
    spokes.each { |spoke| relate(hub, spoke) }
    relate(spokes[0], spokes[1])

    result = graph(cap: 3)

    assert_equal [ pid(hub), pid(spokes[0]), pid(spokes[1]) ].sort, result[:nodes].map { |n| n[:id] }.sort
    assert_equal 5, result[:total]
    assert_equal 3, result[:shown]
    assert result[:edges].all? { |edge| [ edge[:source], edge[:target] ].all? { |id| result[:nodes].any? { |n| n[:id] == id } } }, "an edge points at a post that was cut"
  end

  test "equal connection counts break by newest, then id, so the cut is stable" do
    posts = 4.times.map { |i| create_post(title: "P#{i}") }
    relate(posts[0], posts[1])
    relate(posts[2], posts[3])
    posts.each_with_index { |post, i| post.update_columns(updated_at: Time.zone.local(2026, 1, 1) + i.days) }

    assert_equal [ pid(posts[2]), pid(posts[3]) ], graph(cap: 2)[:nodes].map { |n| n[:id] }
    assert_equal graph(cap: 2), graph(cap: 2)
  end

  test "a tag's count stays the readable number when the cap cuts some of its posts" do
    hub = create_post(title: "Hub", tags: [ "wide" ])
    others = 3.times.map { |i| create_post(title: "T#{i}", tags: [ "wide" ]) }
    relate(hub, others[0])

    tag = graph(cap: 2)[:tags].first

    assert_equal 4, tag[:count]
    assert_equal 2, tag[:degree]
  end

  test "an actor sees only readable posts, no edge to an unreadable one, and no count that includes one" do
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    access_control_grants(:author_posts_create).update!(scope: { "own" => true }) # posts.create implies a read, so it is narrowed too
    own = 2.times.map { |i| create_post(title: "Own #{i}", tags: [ "t" ]).tap { |post| post.update_column(:author_id, users(:author).id) } }
    other = create_post(title: "Other", tags: [ "t" ])
    relate(own[0], other)

    result = as(users(:author)) { graph(actor: users(:author)) }

    assert_equal own.map { |post| pid(post) }, result[:nodes].map { |n| n[:id] }
    assert_equal 2, result[:tags].first[:count]
    assert result[:edges].none? { |edge| edge[:source] == pid(other) || edge[:target] == pid(other) }
    assert_equal 2, result[:total]
  end

  test "a trashed post is no node and makes no tag shared" do
    a = create_post(title: "A", tags: [ "t" ])
    gone = create_post(title: "Gone", tags: [ "t" ])
    relate(a, gone)
    gone.update_column(:trashed_at, Time.current)

    result = graph

    assert_empty result[:nodes]
    assert_empty result[:tags]
    assert_equal 1, result[:isolated]
  end

  test "no posts: empty lists and zero counts" do
    assert_equal({ nodes: [], tags: [], pages: [], types: [], edges: [], total: 0, shown: 0, isolated: 0 }, graph)
  end

  test "the number of statements does not grow with the posts" do
    build = ->(count) do
      posts = count.times.map { |i| create_post(title: "N#{count}-#{i}", tags: [ "bulk" ]) }
      posts.each_cons(2) { |a, b| relate(a, b) }
    end
    build.call(3)
    few = capture_sql { graph }.size
    build.call(12)
    many = capture_sql { graph }.size

    assert_equal few, many
  end

  test "posts are loaded with only the columns a node needs" do
    a = create_post(title: "A")
    relate(a, create_post(title: "B"))

    statements = capture_sql { graph }

    assert statements.none? { |sql| sql.include?('"posts".*') }, "a whole post row was loaded:\n#{statements.grep(/"posts"/).join("\n")}"
  end

  test "a node carries its post's open notes, and the count costs one statement whatever the number of threads" do
    a = create_post(title: "A")
    b = create_post(title: "B")
    relate(a, b)
    as(users(:two)) do
      2.times { Notes::Start.call(a, body: "A note") }
      Notes::Resolve.call(Notes::Start.call(b, body: "Done").record)
    end

    nodes = graph[:nodes].index_by { |node| node[:id] }
    assert_equal [ 2, 0 ], [ nodes[pid(a)][:open_notes], nodes[pid(b)][:open_notes] ]

    few = capture_sql { graph }.size
    as(users(:two)) { 7.times { Notes::Start.call(b, body: "More") } }
    assert_equal few, capture_sql { graph }.size
  end

  # The badge is neutral (handoff, "Mind graph node badge"): what is unread
  # for the viewer is said on the card's rows, never on the node. So the
  # graph's data says nothing about the viewer's deliveries, and reads none.
  test "a node says nothing about what is unread for the viewer, and no delivery is read for the graph" do
    a = create_post(title: "A")
    relate(a, create_post(title: "B"))
    as(users(:two)) { Notes::Start.call(a, body: "For @[#{users(:one).id}]") }
    viewer = users(:one)

    statements = capture_sql { assert(graph(actor: viewer)[:nodes].none? { |node| node.key?(:unread_notes) }) }

    assert_equal 1, statements.count { |sql| sql.include?("note_threads") }
    assert_empty statements.grep(/note_deliveries/)
  end

  test "every readable page is a node, in tree order, with its path, depth, parent and counts" do
    home = root_page
    blog = create_page(title: "Blog")
    child = create_page(title: "Child", parent: blog)
    list_block(blog, content_type: "blog")
    create_post(title: "A")
    as(users(:two)) { Notes::Start.call(blog, body: "A note") }

    pages = graph[:pages]

    assert_equal [ page_id(home), page_id(blog), page_id(child) ], pages.map { |page| page[:id] }
    assert_equal({ id: page_id(blog), title: "Blog", path: "/blog", depth: 1, home: false, parent: page_id(home), order: 1, status: "live",
                   url: "/cs-studio/pages/#{blog.id}", degree: 3, child_count: 1, listed_count: 1, open_notes: 1 }, pages[1].except(:changes, :change_at))
    assert_equal [ true, nil, 0, 1 ], pages[0].values_at(:home, :parent, :depth, :child_count)
  end

  # Design answer H2: "All posts" shows the site total. Every post the
  # viewer reads, one of a type that is no longer registered included (which
  # a block with no filter does not list), and no post they cannot read.
  test "All posts counts every readable post, a retired type's included, and a type's hub its own" do
    list_block(root_page)
    list_block(root_page, content_type: "resume_entry")
    create_post(title: "Blog one")
    create_post(title: "Entry", content_type: "resume_entry")
    create_post(title: "Old talk").update_column(:content_type, "talk")
    create_post(title: "A draft", published: false)

    assert_equal [ [ "type-resume_entry", 1 ], [ "all-posts", 4 ] ], graph[:types].map { |type| type.values_at(:id, :count) }
    assert_equal 3, graph[:pages].first[:listed_count], "what the page lists is not the site's total: no block lists the post of a retired type"

    %i[author_posts_read author_posts_create author_posts_edit].each { |grant| access_control_grants(grant).update!(scope: { "content_types" => [ "resume_entry" ] }) }
    assert_equal [ [ "type-resume_entry", 1 ], [ "all-posts", 1 ] ], as(users(:author)) { graph(actor: users(:author)) }[:types].map { |type| type.values_at(:id, :count) },
      "for a narrowed viewer, the posts THEY read"
  end

  test "a tree line joins a page to its parent, and a lists line a page to its tag, its type or All posts" do
    home = root_page
    by_tag = create_page(title: "By tag")
    by_type = create_page(title: "By type")
    list_block(home)
    list_block(by_tag, tag: "ruby")
    list_block(by_type, content_type: "resume_entry")
    create_post(title: "A", tags: [ "ruby" ])
    tag = "tag-#{Tag.find_by!(name: "ruby").id}"

    result = graph
    lines = result[:edges].reject { |edge| %w[related tag].include?(edge[:kind]) }

    assert_equal [ { source: page_id(by_tag), target: page_id(home), kind: "tree" }, { source: page_id(by_type), target: page_id(home), kind: "tree" },
                   { source: page_id(home), target: "all-posts", kind: "lists" }, { source: page_id(by_tag), target: tag, kind: "lists" },
                   { source: page_id(by_type), target: "type-resume_entry", kind: "lists" } ].sort_by(&:to_s), lines.sort_by(&:to_s)
    assert_equal [ "type-resume_entry", "all-posts" ], result[:types].map { |type| type[:id] }, "All posts is last"
    assert_equal({ id: "type-resume_entry", name: "resume_entry", label: ContentTypes.fetch("resume_entry").label,
                   colour_index: ContentTypes.fetch("resume_entry").colour_index, count: 0, degree: 1 }, result[:types].first)
    assert_equal({ id: "all-posts", name: nil, label: nil, colour_index: nil, count: 1, degree: 1 }, result[:types].last)
  end

  test "a type node joins only the pages that list it, never a post of its type" do
    list_block(create_page(title: "Blog"), content_type: "blog")
    a = create_post(title: "A")
    relate(a, create_post(title: "B"))

    result = graph
    ends = result[:edges].select { |edge| [ edge[:source], edge[:target] ].include?("type-blog") }

    assert_equal [ "lists" ], ends.map { |edge| edge[:kind] }
    assert ends.all? { |edge| edge[:source].start_with?("page-") }
    assert_empty result[:edges].select { |edge| edge[:kind] == "brings" }, "a hub's lines to its posts are a page's local view's, never the whole graph's"
  end

  test "one All posts node however many pages list everything" do
    3.times { |index| list_block(create_page(title: "All #{index}")) }

    result = graph

    assert_equal 1, result[:types].count { |type| type[:id] == "all-posts" }
    assert_equal 3, result[:types].last[:degree]
  end

  test "a listed tag is a node whenever its page is readable, and the one post that carries it is drawn" do
    list_block(create_page(title: "Ruby"), tag: "ruby")
    post = create_post(title: "Only one", tags: [ "ruby" ])
    tag = Tag.find_by!(name: "ruby")

    result = graph

    assert_equal [ { id: "tag-#{tag.id}", name: "ruby", count: 1, degree: 2 } ], result[:tags], "one readable post carries it: the count stays the readable posts"
    assert_equal [ pid(post) ], result[:nodes].map { |node| node[:id] }
    assert_equal 0, result[:isolated]
  end

  test "a listed tag no readable post carries is still a node, with a count of nothing" do
    list_block(create_page(title: "Empty"), tag: "empty")
    tag = Tag.create!(name: "empty")

    assert_equal [ { id: "tag-#{tag.id}", name: "empty", count: 0, degree: 1 } ], graph[:tags]
  end

  test "a lists line is not a post's connection: a post only a page lists is still isolated, and a drawn post says whether a page lists it" do
    list_block(create_page(title: "Blog"), content_type: "blog")
    a = create_post(title: "A")
    relate(a, create_post(title: "B"))
    create_post(title: "Alone")
    entry = create_post(title: "Entry", content_type: "resume_entry")
    relate(entry, a)

    result = graph

    assert_equal 1, result[:isolated]
    assert_equal({ pid(a) => true, pid(entry) => false }, result[:nodes].to_h { |node| [ node[:id], node[:listed] ] }.slice(pid(a), pid(entry)))
  end

  test "a retired type a block names is a type node with no colour" do
    list_block(create_page(title: "Old"), content_type: "gone/thing")

    assert_equal [ { id: "type-gone/thing", name: "gone/thing", label: "gone/thing", colour_index: nil, count: 0, degree: 1 } ], graph[:types]
  end

  # Design answer H2: the order the list's "Post types" group shows.
  test "post types come in colour-slot order, then the retired ones, then All posts last" do
    page = create_page(title: "Lists")
    list_block(page)
    list_block(page, content_type: "zz/gone")
    list_block(page, content_type: "aa/gone")
    ContentTypes.names.each { |name| list_block(page, content_type: name.to_s) }

    registered = ContentTypes.names.map(&:to_s).sort_by { |name| ContentTypes.fetch(name).colour_index }.map { |name| "type-#{name}" }

    assert_equal registered + [ "type-aa/gone", "type-zz/gone", "all-posts" ], graph[:types].map { |type| type[:id] }
  end

  test "status and changes are Publishing::State's, for a page and a post, in each of the five states, and only a scheduled change has its time" do
    looks = { draft: [ "draft", nil ], scheduled: [ "scheduled", nil ], live: [ "live", nil ],
              live_with_changes: [ "live", "unpublished" ], live_change_scheduled: [ "live", "scheduled" ] }
    facts = { draft: [ nil, false, false ], scheduled: [ 3.days.from_now, false, false ], live: [ 1.day.ago, false, false ],
              live_with_changes: [ 1.day.ago, false, true ], live_change_scheduled: [ 1.day.ago, true, true ] }
    records = facts.to_h do |state, (time, pending, mark)|
      page = create_page(title: "Page #{state}")
      post = create_post(title: "Post #{state}", tags: [ "t" ])
      [ page, post ].each do |record|
        Publishing::Version.take!(record, live_at: 2.days.from_now) if pending
        record.update_columns(published_at: time, unpublished_changes_at: (Time.current if mark)) # version: none (a test sets the facts a state is derived from) # changes: none (a test sets the facts a state is derived from)
      end
      [ state, [ page, post ] ]
    end

    result = graph

    records.each do |state, (page, post)|
      assert_equal state, Publishing::State.of(page.reload).state
      assert_equal looks[state], result[:pages].find { |node| node[:id] == page_id(page) }.values_at(:status, :changes), "page #{state}"
      assert_equal looks[state], result[:nodes].find { |node| node[:id] == pid(post) }.values_at(:status, :changes), "post #{state}"
      times = [ result[:pages].find { |node| node[:id] == page_id(page) }, result[:nodes].find { |node| node[:id] == pid(post) } ].map { |node| node[:change_at] }
      if state == :live_change_scheduled
        times.each { |at| assert_in_delta 2.days.from_now.to_f, at.to_f, 60, "the pending copy's live_at" }
      else
        assert_equal [ nil, nil ], times, state.to_s
      end
    end
  end

  test "a page whose parent is outside the scope is drawn without a tree line and names no parent" do
    hidden = create_page(title: "Hidden")
    seen = create_page(title: "Seen", parent: hidden)
    access_control_grants(:author_pages_read).update!(scope: { "page_ids" => [ seen.id ] })

    result = as(users(:author)) { graph(actor: users(:author)) }

    assert_equal [ page_id(seen) ], result[:pages].map { |page| page[:id] }
    assert_equal [ nil, 1, false ], result[:pages].first.values_at(:parent, :depth, :home)
    assert_empty result[:edges].select { |edge| edge[:kind] == "tree" }
    assert_no_match(/page-#{hidden.id}\b/, result.to_json)
    # `Site#pages` are records that carry the unreadable parent's id: the
    # payload takes a parent from the tree alone, so no key holds that id.
    assert_not result[:pages].first.key?(:parent_id)
    assert_not_includes result[:pages].first.values, hidden.id
  end

  test "a tag only an unreadable page lists is no node, and the page's lines are gone with it" do
    hidden = create_page(title: "Hidden")
    seen = create_page(title: "Seen")
    list_block(hidden, tag: "secret")
    list_block(hidden, content_type: "resume_entry")
    Tag.create!(name: "secret")
    # Two posts of the type the hidden page lists, related so that they are
    # drawn: a post only an UNREADABLE page lists is not listed, to this
    # viewer.
    entry = create_post(title: "Entry", content_type: "resume_entry")
    relate(entry, create_post(title: "Other"))
    access_control_grants(:author_pages_read).update!(scope: { "page_ids" => [ seen.id ] })

    result = as(users(:author)) { graph(actor: users(:author)) }

    assert_empty result[:tags]
    assert_empty result[:types]
    assert_equal [ "related" ], result[:edges].map { |edge| edge[:kind] }
    assert_equal false, result[:nodes].find { |node| node[:id] == pid(entry) }.fetch(:listed)
    assert_equal true, graph[:nodes].find { |node| node[:id] == pid(entry) }.fetch(:listed), "to someone who reads the page it is listed"
    assert_no_match(/Hidden|secret|page-#{hidden.id}\b/, result.to_json, "nothing of the hidden page anywhere in the answer: not its title, its id or the tag it names")
  end

  test "a trashed page is no node, its lines are gone, and its child is drawn without a line to it" do
    gone = create_page(title: "Gone")
    child = create_page(title: "Child", parent: gone)
    list_block(gone, content_type: "blog")
    Page.where(id: gone.id).update_all(trashed_at: Time.current) # version: none (a test trashes one page and leaves its child) # changes: none (a test trashes one page)

    result = graph

    assert_equal [ page_id(root_page), page_id(child) ], result[:pages].map { |page| page[:id] }
    assert_nil result[:pages].last[:parent]
    assert_empty result[:edges]
    assert_empty result[:types]
  end

  test "the global graph costs thirteen statements" do
    page = create_page(title: "Blog")
    list_block(page, tag: "shared")
    a = create_post(title: "A", tags: %w[shared])
    relate(a, create_post(title: "B", tags: %w[shared]))
    as(users(:two)) { Notes::Start.call(a, body: "A note"); Notes::Start.call(page, body: "A note") }
    viewer = users(:one) # loaded here, so the fixture's own read is not counted

    statements = capture_sql { graph(actor: viewer) }

    # The site's five (posts, tag links, pages, list blocks, the tags they
    # name), the relations, and the builder's seven (the tags' names; the
    # pages' paths, notes and pending copies; the posts' notes, pending
    # copies and rows).
    assert_equal 13, statements.size, statements.join("\n")
  end

  test "the statement count is the same for 3 pages and for 30, and for 3 posts and for 30" do
    viewer = users(:one)
    pages = ->(count) { count.times { |index| list_block(create_page(title: "Page #{count}-#{index}"), tag: "shared") } }
    posts = ->(count) { count.times { |index| create_post(title: "Post #{count}-#{index}", tags: %w[shared]) } }
    pages.call(3)
    posts.call(3)
    few = capture_sql { graph(actor: viewer) }.size

    pages.call(27)
    more_pages = capture_sql { graph(actor: viewer) }.size
    posts.call(27)
    more_posts = capture_sql { graph(actor: viewer) }.size

    assert_equal [ few, few ], [ more_pages, more_posts ]
  end

  test "above the threshold the answer is where to open, with the number of lines, and no graph" do
    home = root_page
    3.times { |index| create_page(title: "Page #{index}") }
    Tag.create!(name: "listed")
    list_block(home, tag: "listed")

    statements = capture_sql { @answer = graph(open_above: 3) }

    assert_equal({ open: page_id(home), edges: 4 }, @answer, "three tree lines and one lists line")
    assert_equal 6, statements.size, "the site's five and the relations: no node is built"
    assert_equal 4, graph(open_above: 4)[:edges].size, "exactly the threshold is not above it"
  end

  test "everything=1 answers the whole graph whatever its size" do
    3.times { |index| create_page(title: "Page #{index}") }

    assert_equal 4, graph(open_above: 2, everything: true)[:pages].size
  end

  test "over the threshold without a readable Home the whole graph is answered" do
    branch = create_page(title: "Branch")
    3.times { |index| create_page(title: "Leaf #{index}", parent: branch) }
    access_control_grants(:author_pages_read).update!(scope: { "page_ids" => [ branch.id ] })

    result = as(users(:author)) { graph(actor: users(:author), open_above: 2) }

    assert_nil result[:open]
    assert_equal 4, result[:pages].size
  end

  test "over the threshold with no page at all the graph of posts is answered" do
    assert_not Page.exists?, "this test is about a site with no page: `create_post` makes none"
    a = create_post(title: "A")
    relate(a, create_post(title: "B"))

    result = graph(open_above: 0)

    assert_nil result[:open]
    assert_equal [ [], 1 ], [ result[:pages], result[:edges].size ]
  end

  # The posts half of the rights rule, by a viewer narrowed by POST rights:
  # an unreadable post is no node, is in no count and at the end of no line,
  # and a tag only unreadable posts carry is no node.
  test "a post outside the viewer's posts scope is no node, in no count and at no line's end, and a tag only such posts carry is no node" do
    %i[author_posts_read author_posts_create author_posts_edit].each { |grant| access_control_grants(grant).update!(scope: { "content_types" => [ "blog" ] }) }
    mine = 2.times.map { |index| create_post(title: "Mine #{index}", tags: [ "shared" ]) }
    theirs = 2.times.map { |index| create_post(title: "Theirs #{index}", content_type: "resume_entry", tags: %w[shared secret]) }
    relate(mine.first, theirs.first)
    relate(theirs.first, theirs.last)
    page = create_page(title: "Lists")
    list_block(page)
    list_block(page, content_type: "resume_entry")
    shared, secret = %w[shared secret].map { |name| Tag.find_by!(name: name) }
    assert_equal 2, graph[:tags].size, "for trusted code both tags are nodes: what follows is the scope's doing"

    result = as(users(:author)) { graph(actor: users(:author)) }

    assert_equal mine.map { |post| pid(post) }, result[:nodes].map { |node| node[:id] }
    assert_equal [ { id: "tag-#{shared.id}", name: "shared", count: 2, degree: 2 } ], result[:tags]
    assert_equal [ 2, 2, 0 ], result.values_at(:total, :shown, :isolated)
    assert_equal [ [ "type-resume_entry", 0 ], [ "all-posts", 2 ] ], result[:types].map { |type| type.values_at(:id, :count) }
    assert_equal 2, result[:pages].find { |node| node[:id] == page_id(page) }[:listed_count]
    assert_empty result[:edges].select { |edge| edge[:kind] == "related" }
    theirs.each { |post| assert_no_match(/post-#{post.id}\b/, result.to_json) }
    assert_no_match(/tag-#{secret.id}\b|secret|Theirs/, result.to_json)
  end

  # A node's id is its kind AND its database id (pages spec, decision 4): the
  # three tables count on their own, so one number names a page, a post and
  # a tag at once on any site. Each is its own node with its own lines.
  test "a post, a tag and a page of one database id are three nodes, each with its own lines" do
    home = root_page
    # From the SEQUENCES, never from the rows' highest id: in a worker's
    # database the sequences are far ahead of the rows (every rolled-back
    # test moved them on), and `setval` is taken back by no transaction, so
    # an id from the rows would set two of the three back for good. Each
    # only ever moves forward here.
    connection = Page.connection
    id = %w[pages posts tags].map { |table| connection.select_value("SELECT nextval(#{connection.quote(connection.default_sequence_name(table, "id"))})").to_i }.max + 1
    %w[pages posts tags].each { |table| connection.set_pk_sequence!(table, id - 1) }
    page = create_page(title: "Same")
    tag = Tag.create!(name: "same")
    post = create_post(title: "Same post", tags: [ "same" ])
    other = create_post(title: "Other", tags: [ "same" ])
    relate(post, other)
    list_block(page, tag: "same")
    assert_equal [ id, id, id ], [ page.id, tag.id, post.id ], "the test is about one number for all three"

    result = graph
    nodes = (result[:nodes] + result[:tags] + result[:pages]).index_by { |node| node[:id] }

    assert_equal [ "page-#{home.id}", "page-#{id}", "post-#{id}", "post-#{other.id}", "tag-#{id}" ].sort, nodes.keys.sort
    assert_equal [ { source: "post-#{id}", target: "post-#{other.id}", kind: "related" },
                   { source: "post-#{id}", target: "tag-#{id}", kind: "tag" }, { source: "post-#{other.id}", target: "tag-#{id}", kind: "tag" },
                   { source: "page-#{id}", target: "page-#{home.id}", kind: "tree" }, { source: "page-#{id}", target: "tag-#{id}", kind: "lists" } ], result[:edges]
    assert_equal({ "post-#{id}" => 2, "tag-#{id}" => 3, "page-#{id}" => 2 }, nodes.slice("post-#{id}", "tag-#{id}", "page-#{id}").transform_values { |node| node[:degree] })
    assert_equal [ "Same post", "same", "Same" ], [ nodes["post-#{id}"][:title], nodes["tag-#{id}"][:name], nodes["page-#{id}"][:title] ]
    assert_equal [ 1, 1 ], nodes["post-#{id}"].values_at(:related_count, :tag_count)
    assert_equal [ 2, 2 ], [ nodes["page-#{id}"][:listed_count], nodes["tag-#{id}"][:count] ]
  end

  # `Publishing::State` trusts a pending time it is handed, so the graph must
  # hand it exactly what the state would have read itself. Every combination
  # of the three facts that state's own exhaustive test lists (3 x 2 x 2),
  # on a page and on a post; and every record here has a copy IN FORCE (the
  # services took one), which is no pending copy.
  test "for every combination of the time, a pending copy and the mark, a node's status, changes and change_at are what Publishing::State answers by itself" do
    times = { none: nil, future: 3.days.from_now, past: 1.day.ago }
    combinations = times.keys.product([ false, true ], [ false, true ])
    assert_equal 12, combinations.size
    records = combinations.to_h do |time, pending, mark|
      pair = [ create_page(title: "Page #{time} #{pending} #{mark}"), create_post(title: "Post #{time} #{pending} #{mark}", tags: [ "t" ]) ]
      pair.each do |record|
        Publishing::Version.take!(record, live_at: 2.days.from_now) if pending
        record.update_columns(published_at: times.fetch(time), unpublished_changes_at: (Time.current if mark)) # version: none (a test sets the facts a state is derived from) # changes: none (a test sets the facts a state is derived from)
      end
      [ [ time, pending, mark ], pair ]
    end

    result = graph
    nodes = (result[:pages] + result[:nodes]).index_by { |node| node[:id] }

    seen = records.flat_map do |facts, pair|
      pair.map do |record|
        state = Publishing::State.of(record.reload)
        node = nodes.fetch(PostGraph.node_id(record.class.name.underscore, record.id))
        expected = [ state.status, PostGraph::Builder::CHANGES[state.state], (state.pending_at if state.state == :live_change_scheduled) ]
        assert_equal expected, node.values_at(:status, :changes, :change_at), "#{record.class} #{facts.inspect}"
        state.state
      end
    end
    assert_equal Publishing::State::STATES.sort, seen.uniq.sort, "every state was among them"
    assert_equal 4, seen.count(:live_change_scheduled), "a pending copy shows on a live record alone"
  end

  # Two sizes far apart in everything that could cost a statement each: the
  # pages, the list blocks on a page (one of them in a section), the posts,
  # the tags, the notes and the pending copies of pages and of posts.
  test "the statement count is thirteen for a small site and for one ten times its size in pages, blocks, posts, tags, notes and pending copies" do
    viewer = users(:one)
    grow = ->(pages:, blocks:, posts:, tags:, pending:) do
      made = pages.times.map do |index|
        page = create_page(title: "Page #{pages}-#{index}")
        section = ContentBlock.create!(owner: page, block_type: :section, position: 0, settings: { "layout" => "two" })
        ContentBlock.create!(owner: page, block_type: :post_list, position: 0, section_id: section.id, section_column: 1, settings: { "content_type" => "blog" })
        (blocks - 1).times { |block| list_block(page, tag: "tag #{(index + block) % tags}") }
        page
      end
      written = posts.times.map { |index| create_post(title: "Post #{posts}-#{index}", tags: [ "tag #{index % tags}", "tag #{(index + 1) % tags}" ]) }
      written.each_cons(2) { |a, b| relate(a, b) }
      (made.first(pending) + written.first(pending)).each do |record|
        Publishing::Version.take!(record, live_at: 2.days.from_now)
        record.update_columns(unpublished_changes_at: Time.current) # version: none (a test sets the facts a state is derived from) # changes: none (a test sets the facts a state is derived from)
      end
      as(users(:two)) { (made.first(pending) + written.first(pending)).each { |record| Notes::Start.call(record, body: "A note") } }
    end

    grow.call(pages: 3, blocks: 2, posts: 3, tags: 2, pending: 1)
    few = capture_sql { @small = graph(actor: viewer) }
    grow.call(pages: 30, blocks: 4, posts: 40, tags: 20, pending: 10)
    many = capture_sql { @large = graph(actor: viewer) }

    assert_equal [ 4, 3, 2 ], [ @small[:pages].size, @small[:nodes].size, @small[:tags].size ]
    assert_equal [ 34, 43, 20 ], [ @large[:pages].size, @large[:nodes].size, @large[:tags].size ]
    assert_equal 22, (@large[:pages] + @large[:nodes]).count { |node| node[:changes] == "scheduled" }
    assert_equal 13, few.size, few.join("\n")
    assert_equal 13, many.size, many.join("\n")
  end

  # Anyone but an owner costs one statement more, their grants, read once.
  test "for a viewer with a scope the count is the same for a small branch and a large one" do
    branch = create_page(title: "Branch")
    access_control_grants(:author_pages_read).update!(scope: { "page_ids" => [ branch.id ] })
    grow = ->(count) do
      count.times { |index| list_block(create_page(title: "Leaf #{count}-#{index}", parent: branch), tag: "shared") }
      count.times { |index| create_post(title: "Post #{count}-#{index}", tags: %w[shared]) }
    end
    ask = -> do
      Current.reset
      Locales.default # the site's settings, read once a request by whatever asks first: not the graph's
      as(users(:author)) { capture_sql { @answer = graph(actor: users(:author)) } }
    end

    grow.call(2)
    few = ask.call
    small = @answer[:pages].size
    grow.call(25)
    many = ask.call

    assert_equal [ 3, 28 ], [ small, @answer[:pages].size ]
    assert_equal [ 14, 14 ], [ few.size, many.size ], many.join("\n")
  end

  # Every end of every line is a node the answer holds, and every count is
  # the count of the answer's own lines: what the page relies on when it
  # looks an end up among its nodes.
  def assert_whole(graph)
    ids = (graph[:nodes] + graph[:tags] + graph[:pages] + graph[:types] + graph.fetch(:more, [])).to_set { |node| node[:id] }
    loose = graph[:edges].reject { |edge| ids.include?(edge[:source]) && ids.include?(edge[:target]) }
    assert_empty loose, "a line names an id that has no node"
    degree = Hash.new(0)
    graph[:edges].each { |edge| degree[edge[:source]] += 1; degree[edge[:target]] += 1 }
    (graph[:nodes] + graph[:tags] + graph[:pages] + graph[:types]).each { |node| assert_equal degree[node[:id]], node[:degree], "#{node[:id]}: its degree is not the number of its lines" }
    graph[:nodes].each do |node|
      lines = graph[:edges].select { |edge| [ edge[:source], edge[:target] ].include?(node[:id]) }
      assert_equal [ lines.count { |edge| edge[:kind] == "related" }, lines.count { |edge| edge[:kind] == "tag" } ], node.values_at(:related_count, :tag_count), "#{node[:id]}: its two counts are not its lines"
    end
  end

  # Trashes `post` between the site's read and the nodes' (the builder is
  # made after the site is loaded), as an editor's press in another request
  # would.
  def vanishing(post)
    build = PostGraph::Builder.method(:new)
    with_singleton_override(PostGraph::Builder, :new, ->(**options) { post.update_column(:trashed_at, Time.current); build.call(**options) }) { yield } # version: none (a test trashes a post between two reads) # changes: none (a test)
  end

  test "a post that is trashed between the site's read and the nodes' goes whole: no node, no line to it, and every count is of what is left" do
    list_block(create_page(title: "Blog"), content_type: "blog", tag: "t")
    a, b, c = %w[A B C].map { |title| create_post(title: title, tags: [ "t" ]) }
    relate(a, b)
    relate(b, c)
    whole = graph
    assert_whole whole
    assert_equal [ 3, 3, 3 ], [ whole[:nodes].size, whole[:shown], whole[:total] ]

    result = vanishing(b) { graph }

    assert_equal [ pid(a), pid(c) ], result[:nodes].map { |node| node[:id] }.sort
    assert_no_match(/#{pid(b)}\b/, result.to_json, "nothing of the answer names it")
    assert_whole result
    assert_equal [ 2, 2 ], result.values_at(:shown, :total), "it is not one of the posts shown, nor of the connected ones"
    assert_equal 2, result[:tags].find { |tag| tag[:name] == "t" }[:count], "nor one of the posts that carry the tag"
    assert_equal [ [ 1, 0, 1 ] ] * 2, result[:nodes].map { |node| node.values_at(:degree, :related_count, :tag_count) }
  end
end
