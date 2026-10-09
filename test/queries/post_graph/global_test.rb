require "test_helper"

# `PostGraph::Global` (mind graph canvas spec §3.3): the best-connected
# readable posts up to a cap, their tags and edges, and what was left out.
class PostGraph::GlobalTest < ActiveSupport::TestCase
  def graph(actor: nil, cap: PostGraph::CAP) = PostGraph::Global.call(actor: actor, cap: cap, url_for: ->(post) { "/cs-studio/posts/#{post.id}" })

  def relate(a, b) = PostRelation.create!(post: a, related_post: b)

  test "a connected post is a node with its title, type, colour index, status, url and degree" do
    a = create_post(title: "Alpha", content_type: "resume_entry")
    b = create_post(title: "Beta")
    relate(a, b)

    node = graph[:nodes].find { |n| n[:id] == a.id }

    assert_equal({ id: a.id, title: "Alpha", type: "resume_entry", colour_index: ContentTypes.fetch("resume_entry").colour_index,
                   status: "live", url: "/cs-studio/posts/#{a.id}", degree: 1, related_count: 1, tag_count: 0,
                   open_notes: 0, unread_notes: false }, node)
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

    assert_equal [ 1, 2, 3 ], nodes[a.id].values_at(:related_count, :tag_count, :degree)
    assert_equal [ 2, 0, 2 ], nodes[c.id].values_at(:related_count, :tag_count, :degree)
    nodes.each_value { |node| assert_equal node[:degree], node[:related_count] + node[:tag_count] }
  end

  test "the url comes from the given builder" do
    a = create_post(title: "A")
    relate(a, create_post(title: "B"))

    result = PostGraph::Global.call(actor: nil, url_for: ->(record) { "/edit/#{record.id}" })

    assert_equal "/edit/#{a.id}", result[:nodes].find { |n| n[:id] == a.id }[:url]
    assert result[:nodes].none? { |n| n.key?(:color) || n.key?(:colour) }, "no colour value: the page draws from the --cs-cat tokens"
  end

  test "each PostRelation row is exactly one edge" do
    a = create_post(title: "A")
    b = create_post(title: "B")
    relate(a, b)

    assert_equal [ { source: a.id, target: b.id, kind: "related" } ], graph[:edges]
  end

  test "a type that isn't registered any more has no colour index" do
    a = create_post(title: "A")
    relate(a, create_post(title: "B"))
    a.update_column(:content_type, "gone/thing")

    node = graph[:nodes].find { |n| n[:id] == a.id }

    assert_equal [ "gone/thing", nil ], node.values_at(:type, :colour_index)
  end

  test "status is the post's own: draft, scheduled or live" do
    draft, scheduled, live = %w[Draft Scheduled Live].map { |title| create_post(title: title, tags: [ "t" ]) }
    draft.update_column(:published_at, nil)
    scheduled.update_column(:published_at, 2.days.from_now)
    live.update_column(:published_at, 1.day.ago)

    assert_equal({ draft.id => "draft", scheduled.id => "scheduled", live.id => "live" }, graph[:nodes].to_h { |n| [ n[:id], n[:status] ] })
  end

  test "a post with no connection is left out and counted as isolated" do
    a = create_post(title: "A")
    b = create_post(title: "B")
    create_post(title: "Alone")
    relate(a, b)

    result = graph

    assert_equal [ a.id, b.id ], result[:nodes].map { |n| n[:id] }
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
    assert_equal [ { source: a.id, target: "tag-#{tag.id}", kind: "tag" }, { source: b.id, target: "tag-#{tag.id}", kind: "tag" } ], result[:edges]
    assert_equal 1, result[:isolated], "a tag on one post connects nothing"
  end

  test "over the cap the best-connected posts are kept, and total says how many there were" do
    hub = create_post(title: "Hub")
    spokes = 4.times.map { |i| create_post(title: "Spoke #{i}") }
    spokes.each { |spoke| relate(hub, spoke) }
    relate(spokes[0], spokes[1])

    result = graph(cap: 3)

    assert_equal [ hub.id, spokes[0].id, spokes[1].id ].sort, result[:nodes].map { |n| n[:id] }.sort
    assert_equal 5, result[:total]
    assert_equal 3, result[:shown]
    assert result[:edges].all? { |edge| [ edge[:source], edge[:target] ].all? { |id| result[:nodes].any? { |n| n[:id] == id } } }, "an edge points at a post that was cut"
  end

  test "equal connection counts break by newest, then id, so the cut is stable" do
    posts = 4.times.map { |i| create_post(title: "P#{i}") }
    relate(posts[0], posts[1])
    relate(posts[2], posts[3])
    posts.each_with_index { |post, i| post.update_columns(updated_at: Time.zone.local(2026, 1, 1) + i.days) }

    assert_equal [ posts[2].id, posts[3].id ], graph(cap: 2)[:nodes].map { |n| n[:id] }
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

    assert_equal own.map(&:id), result[:nodes].map { |n| n[:id] }
    assert_equal 2, result[:tags].first[:count]
    assert result[:edges].none? { |edge| edge[:source] == other.id || edge[:target] == other.id }
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
    assert_equal({ nodes: [], tags: [], edges: [], total: 0, shown: 0, isolated: 0 }, graph)
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
    assert_equal [ 2, 0 ], [ nodes[a.id][:open_notes], nodes[b.id][:open_notes] ]

    few = capture_sql { graph }.size
    as(users(:two)) { 7.times { Notes::Start.call(b, body: "More") } }
    assert_equal few, capture_sql { graph }.size
  end

  # What turns a node's badge accent (notes spec §4.5): the viewer has an
  # unread delivery on one of the post's OPEN threads. It is read in the
  # statement that counts them, so a viewer costs no statement more than none.
  test "a node says whether its open notes hold something unread for the viewer, in the statement that counts them" do
    a = create_post(title: "A")
    b = create_post(title: "B")
    c = create_post(title: "C")
    relate(a, b)
    relate(b, c)
    as(users(:two)) do
      Notes::Start.call(a, body: "For @[#{users(:one).id}]")
      Notes::Start.call(a, body: "For nobody")
      Notes::Start.call(b, body: "For nobody")
      Notes::Resolve.call(Notes::Start.call(c, body: "Was for @[#{users(:one).id}]").record)
    end

    nodes = graph(actor: users(:one))[:nodes].index_by { |node| node[:id] }
    assert_equal [ [ 2, true ], [ 1, false ], [ 0, false ] ], [ a, b, c ].map { |post| nodes[post.id].values_at(:open_notes, :unread_notes) }
    assert_equal [ false ], graph(actor: users(:two))[:nodes].map { |node| node[:unread_notes] }.uniq, "the author is told nothing about their own notes"
    assert_equal [ false ], graph[:nodes].map { |node| node[:unread_notes] }.uniq, "no viewer, nothing unread"

    viewer = users(:one)
    assert_equal capture_sql { graph }.size, capture_sql { graph(actor: viewer) }.size
    statements = capture_sql { graph(actor: viewer) }
    assert_equal 1, statements.count { |sql| sql.include?("note_threads") }, statements.grep(/note_/).join("\n")
  end

  # Five statements before notes (the readable ids, the relations, the tag
  # links, the posts, the tags' names); the notes add ONE.
  test "the global graph costs six statements" do
    a = create_post(title: "A", tags: %w[shared])
    relate(a, create_post(title: "B", tags: %w[shared]))
    as(users(:two)) { Notes::Start.call(a, body: "A note") }

    viewer = users(:one) # loaded here, so the fixture's own read is not counted

    assert_equal 6, capture_sql { graph(actor: viewer) }.size
  end
end
