require "test_helper"

# The mind graph (design spec §6.1): `PostGraph`'s nodes and edges embedded
# in the page as a JSON data island the `admin--mind-graph` controller
# reads. Same session gate as every other CS Studio screen -- not public.
class Admin::MindGraphTest < ActionDispatch::IntegrationTest
  setup { site_settings(:default).update!(setup_completed_at: Time.current) }

  # Replaces MindGraphTest's (test/integration/mind_graph_test.rb) own
  # "an unauthenticated request cannot reach the mind graph".
  test "an unauthenticated request is redirected to sign-in" do
    get "/cs-studio/mind_graph"
    assert_redirected_to "/cs-studio/sign-in"
  end

  test "embeds nodes with colours and editor urls, and edges" do
    sign_in_as(users(:one))
    a = create_post(title: "Post A")
    b = create_post(title: "Post B", content_type: "resume_entry")
    PostRelation.create!(post: a, related_post: b)

    get "/cs-studio/mind_graph"

    assert_response :success
    data = graph_data
    # Replaces MindGraphTest's own "the mind graph renders every post as a
    # node" -- the full id set, not just one node's own fields (checked
    # separately below), so a post silently missing from the graph would
    # fail here even if every node that *is* present still looks right.
    assert_equal [ a.id, b.id ].sort, data["nodes"].map { |n| n["id"] }.sort
    node = data["nodes"].find { |n| n["id"] == b.id }
    assert_equal "Post B", node["title"]
    assert_equal "resume_entry", node["content_type"]
    assert_equal "#10b981", node["color"]
    assert_equal "/cs-studio/posts/#{b.id}", node["url"]
    assert_equal [ { "source" => a.id, "target" => b.id } ], data["edges"]
    assert_select "nav[aria-label='Modules'] a[href='/cs-studio/mind_graph']", text: "Mind graph"
  end

  test "editor urls keep the editing language" do
    sign_in_as(users(:one))
    with_locales(%w[en de], default: "en")
    post = create_post(title: "Post A")

    get "/cs-studio/mind_graph", params: { locale: "de" }

    assert_equal "/cs-studio/posts/#{post.id}?locale=de", graph_data["nodes"].first["url"]
  end

  test "a title containing </script> can't break out of the data island" do
    sign_in_as(users(:one))
    post = create_post(title: "</script><script>alert(1)</script>")

    get "/cs-studio/mind_graph"

    assert_not_includes response.body, "</script><script>alert(1)"
    assert_equal post.title, graph_data["nodes"].first["title"]
  end

  test "with no posts, an empty state instead of an empty canvas" do
    sign_in_as(users(:one))
    get "/cs-studio/mind_graph"

    assert_response :success
    assert_includes response.body, "No posts yet"
    assert_select "[data-controller~='admin--mind-graph']", count: 0
  end

  private

  def graph_data
    JSON.parse(Nokogiri::HTML::Document.parse(response.body).at_css("script#mind-graph-data[type='application/json']").text)
  end
end
