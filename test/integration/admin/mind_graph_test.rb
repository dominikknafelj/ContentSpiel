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

  test "embeds nodes with colour indexes and editor urls, and edges" do
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
    assert_equal "resume_entry", node["type"]
    assert_equal ContentTypes.fetch("resume_entry").colour_index, node["colour_index"]
    assert_equal "live", node["status"]
    assert_not node.key?("color")
    assert_equal "/cs-studio/posts/#{b.id}", node["url"]
    assert_equal [ { "source" => a.id, "target" => b.id, "kind" => "related" } ], data["edges"]
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

  test "with no posts, 'No posts yet.' in the box instead of an empty canvas" do
    sign_in_as(users(:one))
    get "/cs-studio/mind_graph"

    assert_response :success
    assert_select "[data-mind-graph-empty=no-posts]", text: "No posts yet."
    assert_select "[data-controller~='admin--mind-graph']", count: 0
  end

  test "posts but no connections: the graph is drawn with the message about linking posts" do
    sign_in_as(users(:one))
    create_post(title: "Alone")

    get "/cs-studio/mind_graph"

    assert_select "[data-controller~='admin--mind-graph']"
    assert_select "[data-mind-graph-empty=no-connections]:not(.hidden)", text: "Link posts with Related posts, or give them shared tags, to see connections."
  end

  test "with a connection the message is there but hidden" do
    sign_in_as(users(:one))
    PostRelation.create!(post: create_post(title: "A"), related_post: create_post(title: "B"))

    get "/cs-studio/mind_graph"

    assert_select "[data-mind-graph-empty=no-connections].hidden"
  end

  test "a viewer who can read no post sees 'No posts yet.' however many exist" do
    create_post(title: "Hidden from them")
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    access_control_grants(:author_posts_create).update!(scope: { "own" => true })
    sign_in_as(users(:author))

    get "/cs-studio/mind_graph"

    assert_select "[data-mind-graph-empty=no-posts]", text: "No posts yet."
    assert_not_includes response.body, "Hidden from them"
  end

  test "the legend names only the content types present, plus the shapes" do
    sign_in_as(users(:one))
    create_post(title: "A", content_type: "resume_entry")

    get "/cs-studio/mind_graph"

    assert_select ".admin-mind-graph-legend [data-legend-type]", count: 1
    assert_select "[data-legend-type=resume_entry]", text: /#{ContentTypes.fetch("resume_entry").label}/
    assert_select "[data-legend-type=blog]", count: 0
    assert_select "[data-legend=tag]", text: /Tag/
    assert_select "[data-legend=hollow]", text: /Draft or scheduled/
    assert_select "[data-legend=related]", text: /Related post/
    assert_select "[data-legend=tag-edge]", text: /Shares a tag/
  end

  test "the filter is All, Related and Tags, with All chosen" do
    sign_in_as(users(:one))
    create_post(title: "A")

    get "/cs-studio/mind_graph"

    assert_select "fieldset input[type=radio][name=mind_graph_filter]", count: 3
    assert_select "input#mind-graph-filter-all[checked]"
    assert_select "label[for=mind-graph-filter-related]", text: "Related"
    assert_select "label[for=mind-graph-filter-tag]", text: "Tags"
  end

  test "tag nodes and edges ride in the data island, with only the readable count" do
    sign_in_as(users(:one))
    a = create_post(title: "A")
    b = create_post(title: "B")
    tag = Tag.create!(name: "shared")
    [ a, b ].each { |post| PostTag.create!(post: post, tag: tag) }

    get "/cs-studio/mind_graph"

    data = graph_data
    assert_equal [ { "id" => "tag-#{tag.id}", "name" => "shared", "count" => 2 } ], data["tags"]
    assert_equal [ "tag" ], data["edges"].map { |e| e["kind"] }.uniq
  end

  private

  def graph_data
    JSON.parse(Nokogiri::HTML::Document.parse(response.body).at_css("script#mind-graph-data[type='application/json']").text)
  end
end
