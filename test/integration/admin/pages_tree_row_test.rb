require "test_helper"

# A settings save changes one page's row of the tree and nothing of the
# tree's shape, so its answer replaces that row (`#tree-row-<id>`) and not
# the tree: a burst of autosaves while someone types costs the same however
# many pages the site has. A move, a create and a trash still redraw the tree.
class Admin::PagesTreeRowTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @editor = User.create!(email_address: "tree-editor@example.com", password: "password-password")
    AccessControl::Membership.create!(user: @editor, group: access_control_groups(:editor))
    sign_in_as(@editor)
  end

  def save_settings(page, title:)
    patch admin_page_path(page), as: :turbo_stream,
      params: { base_updated_at: page.reload.settings_changed_at.iso8601(6), page: { title: title } }
    assert_response :success
  end

  def streams = Nokogiri::HTML5.fragment(response.body).css("turbo-stream")

  test "a settings save replaces the saved page's row and not the tree" do
    with_locales(%w[en de es], default: "en") do
      page = create_page(title: "About")

      save_settings(page, title: "About us")

      row = streams.find { |stream| stream["action"] == "replace" && stream["target"] == "tree-row-#{page.id}" }
      assert row, "no stream replaced the saved page's row: #{streams.map { |stream| [ stream["action"], stream["target"] ] }.inspect}"
      template = Nokogiri::HTML5.fragment(row.at_css("template").inner_html)
      assert template.at_css("div#tree-row-#{page.id}.admin-tree-row--selected a[aria-current=page]", text: "About us")
      assert_empty streams.select { |stream| stream["target"] == "tree" }, "a settings save redrew the whole tree"
    end
  end

  # The row answer is drawn under the node the browser keeps, so it says
  # what the person's open set says about the branch below it.
  test "a settings save's row answer reads the open set from the cookie" do
    parent = create_page(title: "Parent")
    create_page(title: "Child", parent: parent)

    cookies[TreeOpenSet::COOKIE] = parent.id.to_s
    save_settings(parent, title: "Parent, opened")
    assert_select "turbo-stream[target='tree-row-#{parent.id}'] template button.admin-tree-row__disclosure[aria-expanded='true']", count: 1

    cookies[TreeOpenSet::COOKIE] = "-#{root_page.id}"
    save_settings(parent, title: "Parent, folded")
    assert_select "turbo-stream[target='tree-row-#{parent.id}'] template button.admin-tree-row__disclosure[aria-expanded='false']", count: 1
  end

  # A cookie is what the browser sends: bytes that are not text fold nothing
  # and break no screen that draws the tree.
  test "a cookie that is not text leaves the Pages screen drawn" do
    page = create_page(title: "About")
    # The test client escapes what it is handed, so the browser's raw
    # `%FF.<id>` reaches the app as the byte 0xFF.
    cookies[TreeOpenSet::COOKIE] = "\xFF.#{page.id}"

    get admin_pages_path
    follow_redirect! while response.redirect?
    assert_response :success
    assert_select "#tree-row-#{page.id}"

    get admin_page_path(page)
    assert_response :success
    assert_select "#tree-row-#{page.id}"
  end

  # The statements of a whole-tree answer were already the same at any size;
  # what grew with the site was the tree read into it and drawn: every
  # visible page's row, sent with every save. So the answer is held at both
  # sizes by its statements, by its size, and by never reading the tree's
  # pages (`AccessControl.tree_visibility`'s pluck, `PageTree.rows`).
  test "a settings save costs the same statements for 3 pages as for 30, answers the same bytes and reads no tree" do
    with_locales(%w[en de es], default: "en") do
      page = create_page(title: "Saved")
      2.times { |index| create_page(title: "Small #{index}") }
      save_settings(page, title: "Warm-up") # the claim, and whatever a first save loads once
      small = capture_sql { save_settings(page, title: "Saved, small site") }
      small_bytes = response.body.bytesize

      27.times { |index| create_page(title: "Large #{index}") }
      save_settings(page, title: "Warm-up again")
      large = capture_sql { save_settings(page, title: "Saved, large site") }
      large_bytes = response.body.bytesize

      assert_operator Page.kept.count, :>=, 30
      assert_equal small.size, large.size, "a settings save ran a statement per page"
      assert_in_delta small_bytes, large_bytes, 64, "a settings save's answer grew with the site: #{small_bytes} bytes for 3 pages, #{large_bytes} for 30"
      tree_reads = large.grep(/"pages"\."id" IN|SELECT "pages"\."id" FROM "pages"/)
      assert_empty tree_reads, "a settings save read the tree's pages"
    end
  end

  # The mark is written beside the save (`Publishing`, a statement of its
  # own), so the row is drawn from the page's row as it is now, never from the
  # record the request holds.
  test "a save of a live page answers its row with the unpublished-changes mark" do
    sign_in_as(users(:one))
    live = create_page(title: "Live page")
    assert_not live.reload.unpublished_changes?

    save_settings(live, title: "Live page, retitled")

    assert live.reload.unpublished_changes?
    assert_select "turbo-stream[target='tree-row-#{live.id}'] template [data-unpublished-changes][aria-label='Unpublished changes']", count: 1
  end

  # The tree column outlives a frame navigation, so a frame answer is no
  # place for the tree: it would be read and sent with every page opened
  # from it. The answer names the page it opens, for the tree's script.
  test "an editor opened in the frame sends no tree" do
    pages = 3.times.map { |index| create_page(title: "Sibling #{index}") }

    get admin_page_path(pages.first), headers: { "Turbo-Frame" => "content" }

    assert_response :success
    assert_select "turbo-frame#content [data-tree-open-page='#{pages.first.id}']", count: 1
    assert_select "turbo-frame#tree", count: 0
    assert_select "li[data-page-id]", count: 0
    pages.each { |page| assert_select "#tree-row-#{page.id}", count: 0 }

    get admin_page_path(pages.first)
    assert_select "turbo-frame#tree li[data-page-id='#{pages.second.id}']"
  end
end
