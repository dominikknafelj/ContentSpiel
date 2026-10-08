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
                   status: "live", url: "/cs-studio/posts/#{a.id}", degree: 1 }, node)
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
end
