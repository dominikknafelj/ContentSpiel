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

  test "a settings save costs the same statements for 3 pages as for 30" do
    with_locales(%w[en de es], default: "en") do
      page = create_page(title: "Saved")
      2.times { |index| create_page(title: "Small #{index}") }
      save_settings(page, title: "Warm-up") # the claim, and whatever a first save loads once
      small = count_statements { save_settings(page, title: "Saved, small site") }

      27.times { |index| create_page(title: "Large #{index}") }
      save_settings(page, title: "Warm-up again")
      large = count_statements { save_settings(page, title: "Saved, large site") }

      assert_operator Page.kept.count, :>=, 30
      assert_equal small, large, "a settings save ran a statement per page"
    end
  end
end
