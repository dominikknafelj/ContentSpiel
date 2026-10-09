require "test_helper"

# The mind graph's two JSON endpoints (mind graph canvas spec §3.1): the
# graph's data, global or around a focus, and the search field's rows. Same
# permission and scope as the screen.
class Admin::MindGraphDataTest < ActionDispatch::IntegrationTest
  setup { site_settings(:default).update!(setup_completed_at: Time.current) }

  def data = response.parsed_body

  test "an unauthenticated request is redirected to sign-in" do
    get "/cs-studio/mind_graph/data"
    assert_redirected_to "/cs-studio/sign-in"
    get "/cs-studio/mind_graph/search", params: { q: "a" }
    assert_redirected_to "/cs-studio/sign-in"
  end

  test "with no focus: the global graph, with totals" do
    sign_in_as(users(:one))
    a = create_post(title: "A")
    b = create_post(title: "B")
    create_post(title: "Alone")
    PostRelation.create!(post: a, related_post: b)

    get "/cs-studio/mind_graph/data"

    assert_response :success
    assert_equal "application/json", response.media_type
    assert_equal [ a.id, b.id ], data["nodes"].map { |n| n["id"] }
    assert_equal [ 2, 2, 1 ], data.values_at("total", "shown", "isolated")
    assert_equal "/cs-studio/posts/#{a.id}", data["nodes"].first["url"]
    assert_nil data["focus"]
  end

  # Notes spec §4.4: every post node says how many open notes its post has,
  # and nothing about the viewer (the badge is neutral).
  test "every node carries its post's open notes" do
    a = create_post(title: "A")
    b = create_post(title: "B")
    PostRelation.create!(post: a, related_post: b)
    as(users(:two)) { Notes::Start.call(a, body: "For @[#{users(:one).id}]") }
    sign_in_as(users(:one))

    get "/cs-studio/mind_graph/data"
    assert_equal [ [ a.id, 1, false ], [ b.id, 0, false ] ], data["nodes"].map { |n| [ n["id"], n["open_notes"], n.key?("unread_notes") ] }

    get "/cs-studio/mind_graph/data", params: { post: b.id }
    assert_equal [ [ a.id, 1, false ], [ b.id, 0, false ] ], data["nodes"].map { |n| [ n["id"], n["open_notes"], n.key?("unread_notes") ] }
  end

  test "post= and depth= answer that post's neighbourhood" do
    sign_in_as(users(:one))
    a = create_post(title: "A")
    b = create_post(title: "B")
    c = create_post(title: "C")
    PostRelation.create!(post: a, related_post: b)
    PostRelation.create!(post: b, related_post: c)

    get "/cs-studio/mind_graph/data", params: { post: a.id }
    assert_equal [ a.id, b.id ], data["nodes"].map { |n| n["id"] }
    assert_equal({ "kind" => "post", "id" => a.id, "node_id" => a.id, "title" => "A", "depth" => 1 }, data["focus"])

    get "/cs-studio/mind_graph/data", params: { post: a.id, depth: 2 }
    assert_equal [ a.id, b.id, c.id ], data["nodes"].map { |n| n["id"] }
  end

  test "tag= answers that tag's neighbourhood" do
    sign_in_as(users(:one))
    a = create_post(title: "A", tags: [ "t" ])
    tag = Tag.find_by!(name: "t")

    get "/cs-studio/mind_graph/data", params: { tag: tag.id }

    assert_equal [ a.id ], data["nodes"].map { |n| n["id"] }
    assert_equal "tag-#{tag.id}", data["focus"]["node_id"]
  end

  test "an unknown, trashed or unreadable focus is 404" do
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    access_control_grants(:author_posts_create).update!(scope: { "own" => true })
    other = create_post(title: "Other")
    gone = create_post(title: "Gone")
    gone.update_column(:trashed_at, Time.current)
    sign_in_as(users(:author))

    [ { post: 0 }, { post: other.id }, { post: gone.id }, { tag: 0 } ].each do |params|
      get "/cs-studio/mind_graph/data", params: params
      assert_response :not_found, "expected 404 for #{params}"
    end
  end

  # A parameter in a shape the screen never sends is answered like any other
  # value that names nothing -- never with a 500.
  test "a parameter that is a list, or a depth that is not a number, is answered without an error" do
    sign_in_as(users(:one))
    a = create_post(title: "A", tags: [ "t" ])
    b = create_post(title: "B", tags: [ "t" ])
    PostRelation.create!(post: a, related_post: b)
    tag = Tag.find_by!(name: "t")

    # A list is not an id: the focus it would name does not exist, so 404, as
    # for `post=abc`. (Not the global graph: the request did ask for a focus.)
    get "/cs-studio/mind_graph/data", params: { post: [ a.id ] }
    assert_response :not_found
    get "/cs-studio/mind_graph/data", params: { tag: [ tag.id ] }
    assert_response :not_found
    get "/cs-studio/mind_graph", params: { post: [ a.id ] }
    assert_response :not_found

    # A depth other than 2 is 1, whatever it is: the documented reading.
    get "/cs-studio/mind_graph/data", params: { post: a.id, depth: "abc" }
    assert_response :success
    assert_equal 1, data["focus"]["depth"]
    get "/cs-studio/mind_graph/data", params: { post: a.id, depth: [ "2" ] }
    assert_response :success
    assert_equal 1, data["focus"]["depth"]

    # A list is not a text to search for: it matches no title and no tag, and
    # the answer is the empty list a search with no match gives.
    get "/cs-studio/mind_graph/search", params: { q: [ "A" ] }
    assert_response :success
    assert_equal [], data
  end

  # The id in the URL is the id in decimal: `?post=010` is post 10.
  test "an id with a leading zero is that id, and a hexadecimal one is not found" do
    sign_in_as(users(:one))
    post = 10.times.map { |i| create_post(title: "Post #{i}") }.last

    get "/cs-studio/mind_graph/data", params: { post: "0#{post.id}" }
    assert_response :success
    assert_equal post.id, data["focus"]["id"]

    get "/cs-studio/mind_graph/data", params: { post: "0x#{post.id.to_s(16)}" }
    assert_response :not_found
  end

  test "editor urls keep the editing language" do
    sign_in_as(users(:one))
    with_locales(%w[en de], default: "en")
    a = create_post(title: "A")
    PostRelation.create!(post: a, related_post: create_post(title: "B"))

    get "/cs-studio/mind_graph/data", params: { locale: "de" }

    assert_equal "/cs-studio/posts/#{a.id}?locale=de", data["nodes"].first["url"]
  end

  test "a viewer without posts.read is refused, as on the screen itself" do
    sign_in_as(users(:editor_branch))

    get "/cs-studio/mind_graph"
    assert_response :forbidden
    get "/cs-studio/mind_graph/data"
    assert_response :forbidden
    get "/cs-studio/mind_graph/search", params: { q: "a" }
    assert_response :forbidden
  end

  test "search answers rows with the url of each row's local view" do
    sign_in_as(users(:one))
    post = create_post(title: "Ruby notes", tags: [ "ruby" ])
    tag = Tag.find_by!(name: "ruby")

    get "/cs-studio/mind_graph/search", params: { q: "rub" }

    assert_equal [
      { "kind" => "post", "id" => post.id, "label" => "Ruby notes", "url" => "/cs-studio/mind_graph?post=#{post.id}" },
      { "kind" => "tag", "id" => tag.id, "label" => "ruby", "url" => "/cs-studio/mind_graph?tag=#{tag.id}" }
    ], data

    get "/cs-studio/mind_graph/search"
    assert_equal [], data
  end
end
