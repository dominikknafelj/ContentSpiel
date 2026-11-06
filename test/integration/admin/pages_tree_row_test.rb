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
end
