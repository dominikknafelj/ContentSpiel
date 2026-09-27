require "test_helper"

# The admin-only mind-graph tool (design spec section 9): Post nodes plus
# PostRelation edges, rendered client-side as a force-directed graph. Same
# session auth gate as every other /avo route -- not public in v1.
class MindGraphTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "editor@example.com", password: "password123")
  end

  test "an unauthenticated request cannot reach the mind graph" do
    get "/avo/mind_graph"

    assert_response :redirect
  end

  test "the mind graph renders every post as a node" do
    sign_in_as(@user)
    post_a = Post.create!(content_type: :blog, title: "Post A")
    post_b = Post.create!(content_type: :resume_entry, title: "Post B")

    get "/avo/mind_graph"

    assert_response :success
    assert_equal [ post_a.id, post_b.id ].sort, graph_nodes(response.body).map { |n| n["id"] }.sort
  end

  # Edges are stored directionally (one PostRelation row) but read as
  # undirected everywhere (page-tree design spec section 4) -- the graph is
  # exactly one such reader, so one row is one edge, not two.
  test "the mind graph renders each PostRelation as one edge" do
    sign_in_as(@user)
    post_a = Post.create!(content_type: :blog, title: "Post A")
    post_b = Post.create!(content_type: :blog, title: "Post B")
    PostRelation.create!(post: post_a, related_post: post_b)

    get "/avo/mind_graph"

    assert_response :success
    assert_equal [ { "source" => post_a.id, "target" => post_b.id } ], graph_edges(response.body)
  end

  # Edges are created explicitly via the Post form's related_posts field
  # (design spec section 9), not by parsing body text -- the graph is a
  # read-only view onto that same data, not a second way to create relations.
  test "a post's node links to its edit page" do
    sign_in_as(@user)
    post = Post.create!(content_type: :blog, title: "Post A")

    get "/avo/mind_graph"

    node = graph_nodes(response.body).find { |n| n["id"] == post.id }
    assert_equal "/avo/resources/posts/#{post.id}/edit", node["editUrl"]
  end

  test "a node carries its post's title and content type" do
    sign_in_as(@user)
    post = Post.create!(content_type: :resume_entry, title: "My Resume Entry")

    get "/avo/mind_graph"

    node = graph_nodes(response.body).find { |n| n["id"] == post.id }
    assert_equal "My Resume Entry", node["title"]
    assert_equal "resume_entry", node["contentType"]
  end

  # The registry's own colour (open-types spec §6), not a map the client
  # hard-codes -- so a type registered later (a plugin, an admin-defined
  # type) gets a graph colour for free, with no JS change.
  test "a node carries its post's content type's colour from the registry" do
    sign_in_as(@user)
    post = Post.create!(content_type: :resume_entry, title: "My Resume Entry")

    get "/avo/mind_graph"

    node = graph_nodes(response.body).find { |n| n["id"] == post.id }
    assert_equal "#10b981", node["color"]
  end

  test "with no posts, the graph shows an empty state instead of an empty canvas" do
    sign_in_as(@user)

    get "/avo/mind_graph"

    assert_response :success
    assert_includes response.body, "No posts yet"
  end

  private

  def graph_nodes(body)
    graph_data(body, "data-mind-graph-nodes-value")
  end

  def graph_edges(body)
    graph_data(body, "data-mind-graph-edges-value")
  end

  def graph_data(body, attribute)
    element = Nokogiri::HTML::Document.parse(body).at_css("[#{attribute}]")
    JSON.parse(element[attribute])
  end
end
