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

  test "the chosen version's own number, or the previous one's, is the default comparison" do
    page = create_page(title: "Pricing")
    publish_title(page, "Pricing and plans")
    publish_title(page, "Pricing for teams")
    sign_in_as users(:one)

    get admin_page_history_path(page, version: 3, with: 3)
    assert_equal "previous", comparison.at_css("select[name=with] option[selected]")["value"]
    get admin_page_history_path(page, version: 3, with: 2)
    assert_equal "previous", comparison.at_css("select[name=with] option[selected]")["value"]
    get admin_page_history_path(page, version: 1, with: 1)
    assert_equal "working", comparison.at_css("select[name=with] option[selected]")["value"]
    get admin_page_history_path(page, version: 3, with: 1)
    assert_equal "1", comparison.at_css("select[name=with] option[selected]")["value"]
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

  # Restoring (version history spec R3, R4, R12, R16): the dialog drawn with
  # the screen, its `_top` form, and the action that calls the service.

  def restore_form = Nokogiri::HTML(response.body).at_css("dialog form[action='#{admin_publishing_restore_path(kind: "page", id: @restored.id)}']")

  # Pricing (version 1), then "Pricing and plans" (version 2, on the site).
  def two_versions
    @restored = create_page(title: "Pricing")
    publish_title(@restored, "Pricing and plans")
    @restored
  end

  def press_restore(record, number: 1, shown: record.reload.updated_at.iso8601(6), headers: {})
    post admin_publishing_restore_path(kind: record.is_a?(Page) ? "page" : "post", id: record.id), params: { number: number, shown_updated_at: shown }, headers: headers
  end

  def english_title(record) = Mobility.with_locale(:en) { record.reload.title }

  test "an owner on a live page is offered Restore, which opens the dialog with its form" do
    page = two_versions
    sign_in_as users(:one)

    get admin_page_history_path(page, version: 1)

    trigger = comparison.at_css("[data-history-restore] button[type=button]")
    assert_equal "Restore version 1…", trigger.text.strip
    dialog = Nokogiri::HTML(response.body).at_css("dialog#history-restore")
    assert dialog, "the dialog is drawn with the screen"
    assert_nil dialog.ancestors("form").first, "the dialog's form stands outside the comparison's GET form"
    assert_equal "1", restore_form.at_css("input[name=number]")["value"]
    assert_equal page.reload.updated_at.iso8601(6), restore_form.at_css("input[name=shown_updated_at]")["value"]
  end

  test "someone with edit and not publish sees a live page's history with no Restore, and a forged restore is refused and audited" do
    page = two_versions
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "pages.edit", scope: {})
    sign_in_as users(:editor_branch)

    get admin_page_history_path(page, version: 1)

    assert_response :success
    assert_nil comparison.at_css("[data-history-restore]")
    assert_select "dialog#history-restore", count: 0

    press_restore(page)

    assert_response :forbidden
    assert_equal "Pricing and plans", english_title(page)
    assert_equal "pages.publish", Audit::Event.where(action: "access.denied", subject: page).sole.metadata["permission"]
    assert_empty Audit::Event.where(action: "page.version_restored")
  end

  test "restore writes the version into the rows, publishes nothing, and lands in the editor with the toast" do
    page = two_versions
    content_version = PublicSite.content_version
    sign_in_as users(:one)

    press_restore(page)

    assert_redirected_to admin_page_path(page)
    assert_equal "Version 1 restored as unpublished changes. Publish changes… puts it on the site.", flash[:notice]
    assert_equal "Pricing", english_title(page)
    assert_equal 2, Publishing.current(page).number, "the site keeps showing version 2"
    assert_equal content_version, PublicSite.content_version
    assert Publishing::State.of(page).changes?
    assert Audit::Event.where(action: "page.version_restored", subject: page).exists?
  end

  test "restore is refused while another tab holds a block of the page, and nothing is written" do
    page = two_versions
    block = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }).record
    publish_changes(page)
    users(:two).update!(name: "Dana Weiss")
    reserve(block, page, users(:two), "tab-bbbbbbbb")
    sign_in_as users(:one)

    press_restore(page, headers: { "X-Notes-Tab" => "tab-aaaaaaaa" })

    assert_redirected_to admin_page_history_path(page, version: 1)
    assert_match(/Dana Weiss is editing/, flash[:alert])
    assert_equal "Pricing and plans", english_title(page)
    assert ContentBlock.exists?(block.id)
    assert_empty Audit::Event.where(action: "page.version_restored")
  end

  test "a restore pressed after a colleague's save is refused as stale" do
    page = two_versions
    sign_in_as users(:one)
    shown = page.reload.updated_at.iso8601(6)
    travel 1.second
    assert as(users(:two)) { Pages::Save.call(page.reload, translations: { "en" => { title: "Pricing for teams" } }) }.ok?

    press_restore(page, shown: shown)

    assert_redirected_to admin_page_history_path(page, version: 1)
    assert_equal "This page changed since you opened this. Look at the differences again.", flash[:alert]
    assert_equal "Pricing for teams", english_title(page)
    assert_empty Audit::Event.where(action: "page.version_restored")
  end

  test "restoring a draft's version says Version N restored." do
    page = two_versions
    assert Pages::Save.call(page.reload, attributes: { published: false }).ok?
    sign_in_as users(:one)

    press_restore(page)

    assert_redirected_to admin_page_path(page)
    assert_equal "Version 1 restored.", flash[:notice]
    assert_equal "Pricing", english_title(page)
    assert_nil page.reload.published_at
  end
end
