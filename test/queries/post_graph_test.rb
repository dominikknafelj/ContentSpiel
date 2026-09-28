require "test_helper"

# `PostGraph` (design spec §6.1): every post as a node, every
# `PostRelation` row as one undirected edge -- the data behind CS Studio's
# mind graph (spec §6.2).
class PostGraphTest < ActiveSupport::TestCase
  test "every post is a node with its title, type, registry colour and editor url" do
    post = create_post(title: "My Resume Entry", content_type: "resume_entry")

    graph = PostGraph.call

    node = graph[:nodes].find { |n| n[:id] == post.id }
    assert_equal "My Resume Entry", node[:title]
    assert_equal "resume_entry", node[:content_type]
    assert_equal "#10b981", node[:color]
    assert_equal "/cs-studio/posts/#{post.id}", node[:url]
  end

  test "the url comes from the given builder" do
    post = create_post(title: "A")

    graph = PostGraph.call(url_for: ->(record) { "/edit/#{record.id}" })

    assert_equal "/edit/#{post.id}", graph[:nodes].first[:url]
  end

  test "each PostRelation row is exactly one edge" do
    a = create_post(title: "A")
    b = create_post(title: "B")
    PostRelation.create!(post: a, related_post: b)

    assert_equal [ { source: a.id, target: b.id } ], PostGraph.call[:edges]
  end

  test "a type without a colour of its own gets a stable palette colour" do
    post = create_post(title: "A")
    post.update_column(:content_type, "gone/thing")

    first = PostGraph.call[:nodes].first[:color]
    assert_match(/\A#\h{6}\z/, first)
    assert_equal first, PostGraph.call[:nodes].first[:color]
    assert_includes PostGraph::PALETTE, first
  end

  test "no posts means no nodes and no edges" do
    assert_equal({ nodes: [], edges: [] }, PostGraph.call)
  end
end
