require "test_helper"

# The History screen of a page or a post (version history spec §3, R4, R14,
# R15): the versions in a rail, the comparison of one with another or with the
# working version, found through the `<kind>s.edit` scope.
class Admin::HistoryTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
  end

  # Publishes `record` again with its English title changed, as an editor would.
  def publish_title(record, title)
    service = record.is_a?(Page) ? Pages::Save : Posts::Save
    assert service.call(record.reload, translations: { "en" => { title: title } }).ok?
    publish_changes(record)
  end

  def versions_rail = Nokogiri::HTML(response.body).at_css("[data-history-versions]")

  def comparison = Nokogiri::HTML(response.body).at_css("[data-history-comparison]")

  test "an editor sees a page's versions newest first, the copy in force marked Live" do
    page = create_page(title: "Pricing")
    publish_title(page, "Pricing and plans")
    publish_title(page, "Pricing for teams")
    sign_in_as users(:one)

    get admin_page_history_path(page)

    assert_response :success
    rows = versions_rail.css("[data-version-row]")
    assert_equal [ "working", "3", "2", "1" ], rows.map { |row| row["data-version-row"] }
    assert_equal [ "Live" ], rows.select { |row| row.at_css(".admin-status-chip") }.map { |row| row.at_css(".admin-status-chip").text.strip }
    assert rows[1].at_css(".admin-status-chip"), "the newest copy is the one in force"
    assert_equal "true", rows[1].at_css("a")["aria-current"], "the newest copy is chosen by default"
    assert_includes response.body, "Back to editor"
    assert_select "a[href=?]", admin_page_path(page), text: /Back to editor/
  end

  test "version 5 is compared with the version before it by default, and with the working version on asking" do
    page = create_page(title: "Pricing")
    publish_title(page, "Pricing and plans")
    publish_title(page, "Pricing for teams")
    assert Pages::Save.call(page.reload, translations: { "en" => { title: "Pricing for everyone" } }).ok?
    sign_in_as users(:one)

    get admin_page_history_path(page, version: 2)

    assert_equal "Version 2", comparison.at_css("h2").text.strip
    chosen = comparison.at_css("select[name=with] option[selected]")
    assert_equal "previous", chosen["value"]
    assert_equal "the version before it (1)", chosen.text.strip
    box = comparison.at_css("[data-diff-field]").text
    assert_includes box, "Pricing"
    assert_includes box, "plans"
    assert_not_includes box, "everyone"

    get admin_page_history_path(page, version: 2, with: "working")

    assert_equal "working", comparison.at_css("select[name=with] option[selected]")["value"]
    box = comparison.at_css("[data-diff-field]").text
    assert_includes box, "plans"
    assert_includes box, "everyone"
  end

  test "the first version is compared with the working version, since nothing comes before it" do
    page = create_page(title: "Pricing")
    assert Pages::Save.call(page.reload, translations: { "en" => { title: "Prices" } }).ok?
    sign_in_as users(:one)

    get admin_page_history_path(page, version: 1)

    assert_equal "working", comparison.at_css("select[name=with] option[selected]")["value"]
    assert_nil comparison.at_css("select[name=with] option[value=previous]")
    assert_includes comparison.at_css("[data-diff-field]").text, "Prices"
  end

  test "the language select names the languages that differ" do
    page = create_page(title: "Pricing", translations: { "de" => { title: "Preise" }, "es" => { title: "Precios" } })
    assert Pages::Save.call(page.reload, translations: { "de" => { title: "Preise und Pläne" } }).ok?
    publish_changes(page)
    sign_in_as users(:one)

    get admin_page_history_path(page, version: 2)

    options = comparison.css("select[name=locale] option")
    assert_equal %w[en de es], options.map { |option| option["value"] }
    assert_equal [ "English", "Deutsch · differs", "Español" ], options.map { |option| option.text.strip }
    assert_includes comparison.text, "No differences.", "English is the same in both"

    get admin_page_history_path(page, version: 2, locale: "de")

    assert_equal "de", comparison.at_css("select[name=locale] option[selected]")["value"]
    assert_includes comparison.at_css("[data-diff-field]").text, "Pläne"
  end

  test "a record outside the viewer's scope is not found" do
    branch = create_page(title: "Branch")
    outside = create_page(title: "Outside")
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "pages.edit", scope: { "page_ids" => [ branch.id ] })
    sign_in_as users(:editor_branch)

    get admin_page_history_path(outside)
    assert_response :not_found

    get admin_page_history_path(branch)
    assert_response :success
  end

  test "someone without edit is not found" do
    page = create_page(title: "Pricing")
    post_record = create_post(title: "News")
    sign_in_as users(:reader)

    get admin_page_history_path(page)
    assert_response :not_found
    get admin_post_history_path(post_record)
    assert_response :not_found
  end

  test "a trashed record and a version that does not exist are not found" do
    page = create_page(title: "Pricing")
    sign_in_as users(:one)

    get admin_page_history_path(page, version: 9)
    assert_response :not_found

    assert Trash::Move.call(page).ok?
    get admin_page_history_path(page)
    assert_response :not_found
  end

  test "someone with edit and not publish on a live page sees the history and no Restore" do
    branch = create_page(title: "Branch")
    page = create_page(title: "Pricing", parent: branch)
    publish_title(page, "Pricing and plans")
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "pages.edit", scope: { "page_ids" => [ branch.id ] })
    sign_in_as users(:editor_branch)

    get admin_page_history_path(page, version: 1)

    assert_response :success
    assert_equal "Version 1", comparison.at_css("h2").text.strip
    assert_nil comparison.at_css("[data-history-restore]")
    assert_not_includes response.body, "Restore version"
  end

  test "an author sees the history of their own live post" do
    record = create_post(title: "News")
    record.update_column(:author_id, users(:author).id) # version: none (a test hands the post to its author) # changes: none (a test)
    publish_title(record, "News today")
    sign_in_as users(:author)

    get admin_post_history_path(record)

    assert_response :success
    assert_equal [ "working", "2", "1" ], versions_rail.css("[data-version-row]").map { |row| row["data-version-row"] }
    assert_select "a[href=?]", admin_post_path(record), text: /Back to editor/
  end

  test "a page never published shows the empty state" do
    page = create_page(title: "Draft", published: false)
    sign_in_as users(:one)

    get admin_page_history_path(page)

    assert_response :success
    assert_includes response.body, "No versions yet"
    assert_includes response.body, "A version is kept each time this page is published."
    assert_nil comparison
    assert_equal [ "working" ], versions_rail.css("[data-version-row]").map { |row| row["data-version-row"] }
  end

  test "the versions are paged fifty to a page" do
    page = create_page(title: "Pricing")
    50.times { Publishing::Version.take!(page.reload, by: users(:one)) } # version: none (a test takes copies)
    sign_in_as users(:one)

    get admin_page_history_path(page, page: 2)

    assert_response :success
    assert_equal [ "working", "1" ], versions_rail.css("[data-version-row]").map { |row| row["data-version-row"] }
    assert_select "[data-history-versions] nav a[href=?]", admin_page_history_path(page, page: 1)
  end

  test "the editor's menu offers History, and Activity links to it" do
    page = create_page(title: "Pricing")
    sign_in_as users(:one)

    get admin_page_path(page)
    assert_select "a[href=?]", admin_page_history_path(page), text: "History"

    get admin_audit_events_path(subject_type: "Page", subject_id: page.id)
    assert_select "a[href=?]", admin_page_history_path(page), text: /History/
  end

  test "the editor's menu offers no History to someone who may only read" do
    page = create_page(title: "Pricing")
    sign_in_as users(:reader)

    get admin_page_path(page)

    assert_response :success
    assert_select "a[href=?]", admin_page_history_path(page), count: 0
  end
end
