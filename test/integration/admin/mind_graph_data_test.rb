require "test_helper"

# The mind graph's two JSON endpoints (mind graph canvas spec §3.1): the
# graph's data, global or around a focus, and the search field's rows. Same
# permission and scope as the screen.
class Admin::MindGraphDataTest < ActionDispatch::IntegrationTest
  setup { site_settings(:default).update!(setup_completed_at: Time.current) }

  def data = response.parsed_body
  def pid(post) = "post-#{post.id}"

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
    assert_equal [ pid(a), pid(b) ], data["nodes"].map { |n| n["id"] }
    assert_equal [ 2, 2, 1 ], data.values_at("total", "shown", "isolated")
    assert_equal "/cs-studio/posts/#{a.id}", data["nodes"].first["url"]
    assert_nil data["focus"]
    assert_equal [ [], [] ], data.values_at("pages", "types")
  end

  test "pages, post types and the two new lines are in the data, with a page's editor url" do
    sign_in_as(users(:one))
    blog = create_page(title: "Blog")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: blog), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).ok?

    get "/cs-studio/mind_graph/data"

    assert_response :success
    assert_equal [ "page-#{root_page.id}", "page-#{blog.id}" ], data["pages"].map { |page| page["id"] }
    assert_equal "/cs-studio/pages/#{blog.id}", data["pages"].last["url"]
    assert_equal [ "type-blog" ], data["types"].map { |type| type["id"] }
    assert_includes data["edges"], { "source" => "page-#{blog.id}", "target" => "page-#{root_page.id}", "kind" => "tree" }
    assert_includes data["edges"], { "source" => "page-#{blog.id}", "target" => "type-blog", "kind" => "lists" }
    assert_nil data["open"], "the whole graph, whatever its size, until the script knows the other answer"
  end

  # Until the script knows the `open` answer (pages plan, Task 8) the screen
  # asks for everything: a site over the threshold would otherwise be
  # answered with an address this script cannot follow. The threshold is
  # put at nothing here, so any graph is over it.
  test "the data is the whole graph however many lines it holds" do
    sign_in_as(users(:one))
    create_page(title: "Blog")
    whole = PostGraph::Global.method(:call)
    assert whole.call(actor: users(:one), url_for: ->(_record) { "" }, open_above: 0).key?(:open), "without the option such a site is told where to open"

    with_singleton_override(PostGraph::Global, :call, ->(**options) { whole.call(**options, open_above: 0) }) do
      get "/cs-studio/mind_graph/data"
    end

    assert_response :success
    assert_nil data["open"]
    assert_equal 2, data["pages"].size
  end

  # Design answer G4: the card's chip says the day a scheduled change comes
  # into force. The query hands up the time; the controller writes the day.
  test "a scheduled change's day is in the data as CS Studio's short date, and a node without one has no such key" do
    sign_in_as(users(:one))
    blog = create_page(title: "Blog")
    at = 3.days.from_now
    Publishing::Version.take!(blog, live_at: at)
    blog.update_columns(unpublished_changes_at: Time.current) # version: none (a test sets the facts a state is derived from) # changes: none (a test sets the facts a state is derived from)

    get "/cs-studio/mind_graph/data"
    page = data["pages"].find { |node| node["id"] == "page-#{blog.id}" }

    assert_equal [ "live", "scheduled", I18n.l(at, format: :"admin.short") ], page.values_at("status", "changes", "change_on")
    assert(data["pages"].reject { |node| node == page }.none? { |node| node.key?("change_on") })
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
    assert_equal [ [ pid(a), 1, false ], [ pid(b), 0, false ] ], data["nodes"].map { |n| [ n["id"], n["open_notes"], n.key?("unread_notes") ] }

    get "/cs-studio/mind_graph/data", params: { post: b.id }
    assert_equal [ [ pid(a), 1, false ], [ pid(b), 0, false ] ], data["nodes"].map { |n| [ n["id"], n["open_notes"], n.key?("unread_notes") ] }
  end

  test "post= and depth= answer that post's neighbourhood" do
    sign_in_as(users(:one))
    a = create_post(title: "A")
    b = create_post(title: "B")
    c = create_post(title: "C")
    PostRelation.create!(post: a, related_post: b)
    PostRelation.create!(post: b, related_post: c)

    get "/cs-studio/mind_graph/data", params: { post: a.id }
    assert_equal [ pid(a), pid(b) ], data["nodes"].map { |n| n["id"] }
    assert_equal({ "kind" => "post", "id" => a.id, "node_id" => pid(a), "title" => "A", "depth" => 1 }, data["focus"])

    get "/cs-studio/mind_graph/data", params: { post: a.id, depth: 2 }
    assert_equal [ pid(a), pid(b), pid(c) ], data["nodes"].map { |n| n["id"] }
  end

  test "tag= answers that tag's neighbourhood" do
    sign_in_as(users(:one))
    a = create_post(title: "A", tags: [ "t" ])
    tag = Tag.find_by!(name: "t")

    get "/cs-studio/mind_graph/data", params: { tag: tag.id }

    assert_equal [ pid(a) ], data["nodes"].map { |n| n["id"] }
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
    page = create_page(title: "Page")

    get "/cs-studio/mind_graph/data", params: { locale: "de" }

    assert_equal "/cs-studio/posts/#{a.id}?locale=de", data["nodes"].first["url"]
    assert_equal "/cs-studio/pages/#{page.id}?locale=de", data["pages"].find { |node| node["id"] == "page-#{page.id}" }["url"]
  end

  # The fixtures' branch editor holds no grant at all; `pages.read` is then
  # given alone.
  test "a viewer with neither pages.read nor posts.read is refused, and one with pages.read alone is answered" do
    create_post(title: "Not theirs")
    blog = create_page(title: "Blog")
    sign_in_as(users(:editor_branch))

    get "/cs-studio/mind_graph"
    assert_response :forbidden
    get "/cs-studio/mind_graph/data"
    assert_response :forbidden
    get "/cs-studio/mind_graph/search", params: { q: "a" }
    assert_response :forbidden

    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "pages.read", scope: {})
    get "/cs-studio/mind_graph/data"

    assert_response :success
    assert_empty data["nodes"]
    assert_equal [ "page-#{root_page.id}", "page-#{blog.id}" ], data["pages"].map { |page| page["id"] }
    assert_equal [ 0, 0, 0 ], data.values_at("total", "shown", "isolated"), "a post they cannot read is not counted as left out either"
    assert_not_includes response.body, "Not theirs"
  end

  # With `pages.read` alone the search is answered (the screen opens for
  # either right) and answers nothing: `PostGraph::Search` narrows posts, and
  # the tags they carry, by `posts.read`.
  test "search answers nothing for a viewer with pages.read alone: no post and no tag a post carries" do
    create_post(title: "Not theirs", tags: [ "nottheirs" ])
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "pages.read", scope: {})
    sign_in_as(users(:editor_branch))

    get "/cs-studio/mind_graph/search", params: { q: "not" }

    assert_response :success
    assert_equal [], data

    sign_in_as(users(:one))
    get "/cs-studio/mind_graph/search", params: { q: "not" }
    assert_equal %w[post tag], data.map { |row| row["kind"] }, "to someone who reads the post both are rows"
  end

  test "search answers rows with the url of each row's local view" do
    sign_in_as(users(:one))
    post = create_post(title: "Ruby notes", tags: [ "ruby" ])
    tag = Tag.find_by!(name: "ruby")

    get "/cs-studio/mind_graph/search", params: { q: "rub" }

    assert_equal [
      { "kind" => "post", "id" => "post-#{post.id}", "record_id" => post.id, "label" => "Ruby notes", "url" => "/cs-studio/mind_graph?post=#{post.id}" },
      { "kind" => "tag", "id" => "tag-#{tag.id}", "record_id" => tag.id, "label" => "ruby", "url" => "/cs-studio/mind_graph?tag=#{tag.id}" }
    ], data

    get "/cs-studio/mind_graph/search"
    assert_equal [], data
  end
end
