require "test_helper"

# `PostGraph` (design spec §6.1): every post as a node, every
# `PostRelation` row as one undirected edge -- the data behind CS Studio's
# mind graph (spec §6.2).
class PostGraphTest < ActiveSupport::TestCase
  test "every post is a node with its title, type, registry colour and editor url" do
    post = create_post(title: "My Resume Entry", content_type: "resume_entry")

    graph = PostGraph.call(actor: nil)

    node = graph[:nodes].find { |n| n[:id] == post.id }
    assert_equal "My Resume Entry", node[:title]
    assert_equal "resume_entry", node[:content_type]
    assert_equal "#10b981", node[:color]
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

    assert_equal [ { source: a.id, target: b.id } ], PostGraph.call(actor: nil)[:edges]
  end

  test "a type without a colour of its own gets a stable palette colour" do
    post = create_post(title: "A")
    post.update_column(:content_type, "gone/thing")

    first = PostGraph.call(actor: nil)[:nodes].first[:color]
    assert_match(/\A#\h{6}\z/, first)
    assert_equal first, PostGraph.call(actor: nil)[:nodes].first[:color]
    assert_includes PostGraph::PALETTE, first
  end

  test "no posts means no nodes and no edges" do
    assert_equal({ nodes: [], edges: [] }, PostGraph.call(actor: nil))
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

    graph = as(users(:author)) { PostGraph.call(actor: users(:author)) }

    assert_equal [ own.id, own_too.id ], graph[:nodes].map { |node| node[:id] }
    assert_equal [ { source: own.id, target: own_too.id } ], graph[:edges]
  end
end
