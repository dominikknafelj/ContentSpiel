require "test_helper"

# The mind graph's page (mind graph canvas spec §3.2): a frame -- heading,
# legend, filter, an empty canvas -- with NO graph data in it. The
# `admin--mind-graph` controller fetches the data from the URL the page names
# (`test/integration/admin/mind_graph_data_test.rb` covers that endpoint) and
# draws it (`test/system/admin/mind_graph_test.rb`). Same session gate as every
# other CS Studio screen -- not public.
class Admin::MindGraphTest < ActionDispatch::IntegrationTest
  setup { site_settings(:default).update!(setup_completed_at: Time.current) }

  # Replaces MindGraphTest's (test/integration/mind_graph_test.rb) own
  # "an unauthenticated request cannot reach the mind graph".
  test "an unauthenticated request is redirected to sign-in" do
    get "/cs-studio/mind_graph"
    assert_redirected_to "/cs-studio/sign-in"
  end

  test "the page is a frame: no graph data in it, and the script is told where to get it" do
    sign_in_as(users(:one))
    a = create_post(title: "A very particular title")
    PostRelation.create!(post: a, related_post: create_post(title: "B"))

    get "/cs-studio/mind_graph"

    assert_response :success
    assert_select "script#mind-graph-data", count: 0
    assert_no_match "A very particular title", response.body
    assert_select "[data-controller='admin--mind-graph'][data-url='/cs-studio/mind_graph/data'][data-state='loading']"
    assert_select "[data-controller='admin--mind-graph'][data-worker-url*='mind_graph/layout_worker'][data-d3-url*='d3-force']"
    assert_select "canvas[role='img'][tabindex='0'][aria-label]"
    assert_select "nav[aria-label='Modules'] a[href='/cs-studio/mind_graph']", text: "Mind graph"
  end

  # The strings the script shows are the server's (docs/reference/i18n.md): a
  # plural rides whole, for the script to choose a form by count.
  test "the script's messages ride on the element" do
    sign_in_as(users(:one))
    create_post(title: "A")

    get "/cs-studio/mind_graph"

    messages = JSON.parse(css_select("[data-controller='admin--mind-graph']").first["data-messages"])
    assert_equal "The graph could not be loaded.", messages["mind_graph.script.load_failed"]
    assert_equal({ "one" => "%{count} post has no connections yet.", "other" => "%{count} posts have no connections yet." }, messages["mind_graph.script.isolated"])
    assert_equal %w[capped isolated load_failed loading no_connections retry summary worker_failed].map { |key| "mind_graph.script.#{key}" },
                 messages.keys.grep(/\Amind_graph/).sort
  end

  test "the data url carries the focus, the depth and the editing language" do
    sign_in_as(users(:one))
    with_locales(%w[en de], default: "en")
    post = create_post(title: "A")

    get "/cs-studio/mind_graph", params: { post: post.id, depth: 2, locale: "de" }

    url = css_select("[data-controller='admin--mind-graph']").first["data-url"]
    assert_equal "/cs-studio/mind_graph/data", URI(url).path
    assert_equal({ "post" => post.id.to_s, "depth" => "2", "locale" => "de" }, Rack::Utils.parse_query(URI(url).query))
  end

  test "a tag focus rides in the data url, and a depth other than 1 or 2 is read as 1" do
    sign_in_as(users(:one))
    create_post(title: "A", tags: [ "t" ])
    tag = Tag.find_by!(name: "t")

    get "/cs-studio/mind_graph", params: { tag: tag.id, depth: 7 }

    url = css_select("[data-controller='admin--mind-graph']").first["data-url"]
    assert_equal({ "tag" => tag.id.to_s, "depth" => "1" }, Rack::Utils.parse_query(URI(url).query))
  end

  test "a focus outside the viewer's scope, in the trash or unknown is 404" do
    sign_in_as(users(:one))
    gone = create_post(title: "Gone")
    gone.update_column(:trashed_at, Time.current)

    [ { post: 0 }, { post: gone.id }, { tag: 0 } ].each do |params|
      get "/cs-studio/mind_graph", params: params
      assert_response :not_found, "expected 404 for #{params}"
    end
  end

  test "a post the viewer may not read is not found as a focus, and neither is a tag only it carries" do
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    access_control_grants(:author_posts_create).update!(scope: { "own" => true })
    own = create_post(title: "Own")
    own.update_column(:author_id, users(:author).id)
    other = create_post(title: "Other", tags: [ "theirs" ])
    sign_in_as(users(:author))

    get "/cs-studio/mind_graph", params: { post: own.id }
    assert_response :success

    [ { post: other.id }, { tag: Tag.find_by!(name: "theirs").id } ].each do |params|
      get "/cs-studio/mind_graph", params: params
      assert_response :not_found, "expected 404 for #{params}"
    end
  end

  test "a viewer who can read no post sees 'No posts yet.' and no canvas, however many exist" do
    create_post(title: "Hidden from them")
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    access_control_grants(:author_posts_create).update!(scope: { "own" => true })
    sign_in_as(users(:author))

    get "/cs-studio/mind_graph"

    assert_select "[data-mind-graph-empty=no-posts]", text: "No posts yet."
    assert_select "canvas", count: 0
    assert_select "[data-controller='admin--mind-graph']", count: 0
    assert_not_includes response.body, "Hidden from them"
  end

  test "with no posts at all, 'No posts yet.' instead of an empty canvas" do
    sign_in_as(users(:one))

    get "/cs-studio/mind_graph"

    assert_response :success
    assert_select "[data-mind-graph-empty=no-posts]", text: "No posts yet."
    assert_select "[data-controller~='admin--mind-graph']", count: 0
  end

  test "the legend names only the content types of the viewer's posts, plus the shapes" do
    sign_in_as(users(:one))
    create_post(title: "A", content_type: "resume_entry")

    get "/cs-studio/mind_graph"

    assert_select ".admin-mind-graph-legend [data-legend-type]", count: 1
    assert_select "[data-legend-type='resume_entry']", text: /#{ContentTypes.fetch("resume_entry").label}/
    assert_select "[data-legend='tag']", text: /Tag/
    assert_select "[data-legend='hollow']", text: /Draft or scheduled/
    assert_select "[data-legend='related']", text: /Related post/
    assert_select "[data-legend='tag-edge']", text: /Shares a tag/
    assert_select "[data-legend='retired']", count: 0
  end

  test "the legend names no content type of a post the viewer can't read" do
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    access_control_grants(:author_posts_create).update!(scope: { "own" => true })
    create_post(title: "Own").update_column(:author_id, users(:author).id)
    create_post(title: "Theirs", content_type: "resume_entry")
    sign_in_as(users(:author))

    get "/cs-studio/mind_graph"

    assert_select "[data-legend-type]", count: 1
    assert_select "[data-legend-type='resume_entry']", count: 0
  end

  test "a post of a type that is no longer registered adds the Retired type entry" do
    sign_in_as(users(:one))
    create_post(title: "A").update_column(:content_type, "gone/thing")

    get "/cs-studio/mind_graph"

    assert_select "[data-legend='retired']", text: /Retired type/
    assert_select "[data-legend-type]", count: 0
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

  test "zoom in, zoom out and Fit all are buttons beside the canvas" do
    sign_in_as(users(:one))
    create_post(title: "A")

    get "/cs-studio/mind_graph"

    { "Zoom in" => "zoomIn", "Zoom out" => "zoomOut", "Fit all" => "fit" }.each do |label, action|
      assert_select "button[type=button][data-action='admin--mind-graph##{action}']", text: label
    end
  end
end
