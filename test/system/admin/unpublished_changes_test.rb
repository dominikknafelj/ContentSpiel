require "application_system_test_case"

# What a live record's header, the page tree, the posts list and the dashboard
# say once its rows have moved on from what is published (drafts plan, task 6).
# The answer to a save carries the header's two publishing parts, so the mark
# appears with the first change and not at the next reload.
class UnpublishedChangesSystemTest < ApplicationSystemTestCase
  HEADER = "header.admin-editor-header".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    Current.set(actor: users(:one)) { @live = create_page(title: "Live page") }
  end

  test "typing in a live page shows the chip, the button and the tree's dot with no reload, and publishing the changes takes them away" do
    sign_in_via_form(users(:one))
    visit admin_page_path(@live)
    await_admin_controllers

    # Both parts are in the header from the start, empty.
    assert_selector "#{HEADER} #publishing-chip", visible: :all
    assert_selector "#{HEADER} #publishing-actions", visible: :all
    assert_no_selector "#{HEADER} [data-unpublished-changes]"
    assert_no_button "Publish changes"
    assert_no_selector "li[data-page-id='#{@live.id}'] [data-unpublished-changes]"

    # One value set in one go, then Tab: the field's own blur saves at once.
    title = find_field("Title")
    title.set("Live page, retitled")
    title.send_keys(:tab)

    assert_selector "#{HEADER} #publishing-chip [data-unpublished-changes]", text: "Unpublished changes"
    assert_selector "#{HEADER} #publishing-actions button", text: "Publish changes"
    assert_selector "li[data-page-id='#{@live.id}'] [data-unpublished-changes][aria-label='Unpublished changes']"
    assert @live.reload.unpublished_changes?
    assert_equal "Live page", Publishing.current(@live).snapshot.dig("fields", "title", "en"), "the site still shows what was published"

    press "Publish changes"

    assert_no_selector "#{HEADER} [data-unpublished-changes]", wait: 10
    assert_no_selector "#{HEADER} #publishing-actions button"
    assert_no_selector "li[data-page-id='#{@live.id}'] [data-unpublished-changes]"
    assert_text "Changes published"
    assert_equal "Live page, retitled", Publishing.current(@live.reload).snapshot.dig("fields", "title", "en")
    assert_not @live.unpublished_changes?
  end

  test "the posts list marks a live post with unpublished changes, and the dashboard lists it under Unpublished changes" do
    Current.set(actor: users(:one)) do
      @marked = create_post(title: "Marked post")
      @plain = create_post(title: "Plain post")
      assert Posts::Save.call(@marked, translations: { "en" => { title: "Marked post, retyped" } }).ok?
    end
    sign_in_via_form(users(:one))

    visit admin_posts_path
    assert_selector "tbody tr", text: "Marked post, retyped"
    assert_selector "tbody tr", text: "Plain post"
    assert_selector "tbody tr [data-unpublished-changes]", count: 1
    assert_selector "tbody tr:has(a[href$='/posts/#{@marked.id}']) [data-unpublished-changes]"

    visit admin_root_path
    assert_selector "section[aria-labelledby=dashboard-unpublished-changes] a[href$='/posts/#{@marked.id}']", text: "Marked post, retyped"
    assert_no_selector "section[aria-labelledby=dashboard-unpublished-changes] a[href$='/posts/#{@plain.id}']"
  end
end
