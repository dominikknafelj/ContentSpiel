require "test_helper"

# The hand-built replacement for Avo's own drag-and-drop reordering (an
# avo-record_reordering add-on, paid): a custom tool rendering the whole Page
# tree, and the endpoint its Stimulus controller calls on every drop. Both are
# gated by the same session auth as every other /avo route -- neither is a
# public endpoint.
class PagesTreeTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "editor@example.com", password: "password123")

    @root = Page.create!(title: "Home", page_type: :standard)
    @about = Page.create!(title: "About", slug: "about", parent: @root)
    @team = Page.create!(title: "Team", slug: "team", parent: @about)
    @blog = Page.create!(title: "Blog", slug: "blog", parent: @root)
  end

  # -- access ------------------------------------------------------------

  test "an unauthenticated request cannot reach the tree page" do
    get "/avo/pages_tree"

    assert_response :redirect
  end

  test "an unauthenticated request cannot reorder a page" do
    # A value that actually differs from @about's current parent -- asserting
    # against its unchanged *current* parent would pass even if the request
    # had gone through unblocked.
    patch "/avo/pages_tree/reorder", params: { page_id: @about.id, parent_id: @blog.id, position: 0 }

    assert_response :redirect
    assert_equal @root.id, @about.reload.parent_id
  end

  # -- rendering -----------------------------------------------------------

  test "the tree page renders every page, nested under its real parent" do
    sign_in_as(@user)

    get "/avo/pages_tree"

    assert_response :success
    doc = Nokogiri::HTML::Document.parse(response.body)
    about_li = doc.at_css(%(li[data-page-id="#{@about.id}"]))
    blog_li = doc.at_css(%(li[data-page-id="#{@blog.id}"]))

    # Team's <li> is a real descendant of About's -- not merely present
    # somewhere in the response -- and is absent from Blog's own subtree.
    assert_includes about_li.css("li").map { |li| li["data-page-id"] }, @team.id.to_s
    assert_not_includes blog_li.css("li").map { |li| li["data-page-id"] }, @team.id.to_s
    assert_equal "/avo/resources/pages/#{@about.id}/edit", about_li.at_css("a")["href"]
  end

  test "the root page has no drag handle, but every other page does" do
    sign_in_as(@user)

    get "/avo/pages_tree"

    doc = Nokogiri::HTML::Document.parse(response.body)
    root_li = doc.at_css(%(li[data-page-id="#{@root.id}"]))
    about_li = doc.at_css(%(li[data-page-id="#{@about.id}"]))

    # `> div` -- the page's own row, not a descendant page's handle bleeding
    # up through `.css` traversing the whole subtree.
    assert_nil root_li.at_css("> div .pages-tree-node__handle")
    assert about_li.at_css("> div .pages-tree-node__handle")
  end

  # -- reordering ------------------------------------------------------------

  test "a valid drop updates the page's parent and position" do
    sign_in_as(@user)

    patch "/avo/pages_tree/reorder", params: { page_id: @team.id, parent_id: @root.id, position: 1 }

    assert_response :success
    assert_equal({ "ok" => true }, response.parsed_body)
    @team.reload
    assert_equal @root.id, @team.parent_id
    assert_equal 1, @team.position
  end

  test "dropping a page under itself is rejected, not applied" do
    sign_in_as(@user)

    patch "/avo/pages_tree/reorder", params: { page_id: @about.id, parent_id: @about.id, position: 0 }

    assert_response :unprocessable_entity
    assert_equal false, response.parsed_body["ok"]
    assert_equal @root.id, @about.reload.parent_id
  end

  test "dropping a page onto its own descendant is rejected, not applied" do
    sign_in_as(@user)

    patch "/avo/pages_tree/reorder", params: { page_id: @about.id, parent_id: @team.id, position: 0 }

    assert_response :unprocessable_entity
    assert_equal @root.id, @about.reload.parent_id
    assert_equal @about.id, @team.reload.parent_id
  end

  test "dropping a page onto a blank parent_id makes it the new root candidate, rejected while one already exists" do
    sign_in_as(@user)

    patch "/avo/pages_tree/reorder", params: { page_id: @about.id, parent_id: "", position: 0 }

    assert_response :unprocessable_entity
    assert_equal @root.id, @about.reload.parent_id
  end
end
