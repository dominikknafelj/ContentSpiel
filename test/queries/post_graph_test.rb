require "test_helper"

# `PostGraph` (design spec §6.1): every post as a node, every
# `PostRelation` row as one undirected edge -- the data behind CS Studio's
# mind graph (spec §6.2).
class PostGraphTest < ActiveSupport::TestCase
  # `url_for:` has no default (a query names no route), so every call says
  # where a post opens: the editor path the controller builds.
  def graph_of(actor) = PostGraph.call(actor: actor, url_for: ->(post) { "/cs-studio/posts/#{post.id}" })

  test "every post is a node with its title, type, colour index, status and editor url" do
    post = create_post(title: "My Resume Entry", content_type: "resume_entry")

    graph = graph_of(nil)

    node = graph[:nodes].find { |n| n[:id] == post.id }
    assert_equal "My Resume Entry", node[:title]
    assert_equal "resume_entry", node[:type]
    assert_equal ContentTypes.fetch("resume_entry").colour_index, node[:colour_index]
    assert_equal "live", node[:status]
    assert_not node.key?(:color), "no colour value: the page draws from the --cs-cat tokens"
    assert_equal "/cs-studio/posts/#{post.id}", node[:url]
  end

  test "the url comes from the given builder" do
    post = create_post(title: "A")

    graph = PostGraph.call(actor: nil, url_for: ->(record) { "/edit/#{record.id}" })

    assert_equal "/edit/#{post.id}", graph[:nodes].first[:url]
  end

  test "each PostRelation row is exactly one edge" do
    a = create_post(title: "A")
    b = create_post(title: "B")
    PostRelation.create!(post: a, related_post: b)

    assert_equal [ { source: a.id, target: b.id, kind: "related" } ], graph_of(nil)[:edges]
  end

  test "a type that isn't registered any more has no colour index" do
    post = create_post(title: "A")
    post.update_column(:content_type, "gone/thing")

    node = graph_of(nil)[:nodes].first
    assert_equal "gone/thing", node[:type]
    assert_nil node[:colour_index]
  end

  test "status is the post's own: draft, scheduled or live" do
    draft = create_post(title: "Draft")
    draft.update_column(:published_at, nil)
    scheduled = create_post(title: "Scheduled")
    scheduled.update_column(:published_at, 2.days.from_now)
    live = create_post(title: "Live")
    live.update_column(:published_at, 1.day.ago)

    statuses = graph_of(nil)[:nodes].to_h { |n| [ n[:id], n[:status] ] }
    assert_equal({ draft.id => "draft", scheduled.id => "scheduled", live.id => "live" }, statuses)
  end

  test "a tag on two readable posts is a tag node with an edge to each" do
    a = create_post(title: "A")
    b = create_post(title: "B")
    c = create_post(title: "C")
    shared = Tag.create!(name: "shared")
    lonely = Tag.create!(name: "lonely")
    [ a, b ].each { |post| PostTag.create!(post: post, tag: shared) }
    PostTag.create!(post: c, tag: lonely)

    graph = graph_of(nil)

    assert_equal [ { id: "tag-#{shared.id}", name: "shared", count: 2 } ], graph[:tags]
    assert_equal [ { source: a.id, target: "tag-#{shared.id}", kind: "tag" }, { source: b.id, target: "tag-#{shared.id}", kind: "tag" } ], graph[:edges]
  end

  test "a trashed post is no node, and does not make a tag shared" do
    a = create_post(title: "A")
    gone = create_post(title: "Gone")
    tag = Tag.create!(name: "shared")
    [ a, gone ].each { |post| PostTag.create!(post: post, tag: tag) }
    gone.update_column(:trashed_at, Time.current)

    graph = graph_of(nil)

    assert_equal [ a.id ], graph[:nodes].map { |n| n[:id] }
    assert_empty graph[:tags]
    assert_empty graph[:edges]
  end

  test "a tag's count and edges are the readable posts only" do
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    access_control_grants(:author_posts_create).update!(scope: { "own" => true })
    own = create_post(title: "Own")
    own_too = create_post(title: "Own too")
    theirs = create_post(title: "Theirs")
    [ own, own_too ].each { |post| post.update_column(:author_id, users(:author).id) }
    shared = Tag.create!(name: "shared")
    hidden_only = Tag.create!(name: "hidden-pair")
    [ own, own_too, theirs ].each { |post| PostTag.create!(post: post, tag: shared) }
    [ own, theirs ].each { |post| PostTag.create!(post: post, tag: hidden_only) }

    graph = as(users(:author)) { graph_of(users(:author)) }

    assert_equal [ { id: "tag-#{shared.id}", name: "shared", count: 2 } ], graph[:tags], "a tag with one readable post disappears, the count leaves out the hidden post"
    assert_equal [ own.id, own_too.id ].sort, graph[:edges].map { |e| e[:source] }.sort
    assert_not_includes graph[:edges].flat_map { |e| [ e[:source], e[:target] ] }, theirs.id
    assert_not_includes graph.to_json, "Theirs"
  end

  test "the number of queries does not grow with the posts and tags" do
    build = lambda do |count|
      tag = Tag.create!(name: "tag-#{count}-#{SecureRandom.hex(3)}")
      count.times { |i| create_post(title: "P#{count}-#{i}").tap { |post| PostTag.create!(post: post, tag: tag) } }
    end
    build.call(2)
    small = count_queries { graph_of(nil) }
    build.call(8)
    Tag.create!(name: "other").tap { |t| Post.limit(3).each { |post| PostTag.create!(post: post, tag: t) } }
    large = count_queries { graph_of(nil) }

    assert_equal small, large
  end

  test "no posts means no nodes and no edges" do
    assert_equal({ nodes: [], tags: [], edges: [] }, graph_of(nil))
  end

  # Access-control design spec §3.3: the graph is the actor's readable
  # posts, and no edge reaches one they can't read. A trusted `actor: nil`
  # (above) sees everything.
  test "an actor sees only readable posts, and no edge to an unreadable one" do
    # Both: an unscoped `posts.create` implies reading every post.
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    access_control_grants(:author_posts_create).update!(scope: { "own" => true })
    own = create_post(title: "Own")
    own_too = create_post(title: "Own too")
    theirs = create_post(title: "Theirs")
    [ own, own_too ].each { |post| post.update_column(:author_id, users(:author).id) }
    PostRelation.create!(post: own, related_post: own_too)
    PostRelation.create!(post: own, related_post: theirs)
    PostRelation.create!(post: theirs, related_post: own_too)

    graph = as(users(:author)) { graph_of(users(:author)) }

    assert_equal [ own.id, own_too.id ], graph[:nodes].map { |node| node[:id] }
    assert_equal [ { source: own.id, target: own_too.id, kind: "related" } ], graph[:edges]
  end

  private

  def count_queries(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end
