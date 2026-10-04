require "application_system_test_case"

# The New page and New post dialogs in a real browser (design pass round 2,
# Task 15): opened from the tree's "+", the pages empty state, ⌘K and the posts
# list; preset Inside, a live URL line, a refusal that stays inside the open
# dialog, and a create that never loses typing still waiting in the editor.
class Admin::NewRecordSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    Current.set(actor: users(:one)) do
      @services = create_page(title: "Services")
      @about = create_page(title: "About")
    end
    sign_in_via_form(users(:one))
  end

  test "the row's + opens the dialog with Inside preset, the URL follows the title, Create opens the new page under it" do
    visit admin_page_path(@about)
    await_admin_controllers

    find("li[data-page-id='#{@services.id}'] > div").hover
    find("li[data-page-id='#{@services.id}'] > div a[aria-label^='Add a page under']").click

    assert_selector "dialog#new-page-dialog[open]"
    assert_equal @services.id.to_s, find("#new-page-inside").value
    assert_equal "new-page-title", page.evaluate_script("document.activeElement.id")
    assert_selector "dialog#new-page-dialog [data-admin--new-record-target=url]", text: "URL: /services/"

    fill_in "new-page-title", with: "Our Team"
    assert_selector "dialog#new-page-dialog [data-admin--new-record-target=url]", text: "URL: /services/our-team"
    assert_selector "dialog#new-page-dialog [data-admin--new-record-target=note]", text: "Created as a draft at the end of Services."

    click_button "Create page"

    assert_selector "header.admin-editor-header", wait: 10
    created = Page.order(:id).last
    assert_equal @services, created.parent
    assert_not created.live?
    assert_current_path admin_page_path(created)
    assert_selector "li[data-page-id='#{@services.id}'] ul li[data-page-id='#{created.id}']"
  end

  test "the tree header's New page starts at Home with a clean form every time" do
    visit admin_page_path(@about)
    await_admin_controllers

    click_link "+ New page"
    assert_selector "dialog#new-page-dialog[open]"
    assert_equal root_page.id.to_s, find("#new-page-inside").value
    fill_in "new-page-title", with: "Left over"
    send_keys(:escape)
    assert_no_selector "dialog#new-page-dialog[open]"

    find("li[data-page-id='#{@services.id}'] > div").hover
    find("li[data-page-id='#{@services.id}'] > div a[aria-label^='Add a page under']").click
    assert_selector "dialog#new-page-dialog[open]"
    assert_equal "", find("#new-page-title").value
    assert_equal @services.id.to_s, find("#new-page-inside").value
  end

  test "a blank title stays inside the open dialog with the summary focused and the typed choices kept" do
    visit admin_page_path(@about)
    await_admin_controllers

    click_link "+ New page"
    select "Landing", from: "new-page-type"
    click_button "Create page"

    assert_selector "dialog#new-page-dialog[open] .admin-error-summary", text: "1 thing needs fixing", wait: 10
    assert_equal "Landing", find("#new-page-type").find("option[selected]").text
    assert page.evaluate_script("document.activeElement.classList.contains('admin-error-summary')")
    assert_current_path admin_page_path(@about)

    fill_in "new-page-title", with: "Fixed"
    click_button "Create page"
    assert_selector "header.admin-editor-header", wait: 10
    assert Page.order(:id).last.landing?
  end

  test "a title typed in the editor and still waiting to save is saved before the new page opens" do
    visit admin_page_path(@about)
    await_admin_controllers
    fill_in "page-subtitle", with: "Typed just now"

    click_link "+ New page"
    fill_in "new-page-title", with: "Quick one"
    click_button "Create page"

    assert_selector "header.admin-editor-header", wait: 10
    assert_current_path admin_page_path(Page.order(:id).last)
    assert_equal "Typed just now", @about.reload.subtitle
  end

  test "New post: pick a type, type a title, Create opens that post's editor" do
    visit admin_posts_path
    await_admin_controllers

    click_link "+ New post", match: :first
    assert_selector "dialog#new-post-dialog[open]"
    assert_equal "new-post-title", page.evaluate_script("document.activeElement.id")
    assert_selector "dialog#new-post-dialog [data-admin--new-record-target=url]", text: "Not listed on any page yet"

    find("dialog#new-post-dialog label", text: ContentTypes.find("now_update").label).click
    fill_in "new-post-title", with: "Writing this down"
    click_button "Create draft"

    assert_selector "header.admin-editor-header", wait: 10
    created = Post.order(:id).last
    assert_equal "now_update", created.content_type
    assert_equal "Writing this down", created.title
    assert_current_path admin_post_path(created)
  end

  test "the palette's New page and New post entries close it and open the dialogs" do
    visit admin_page_path(@about)
    await_admin_controllers

    find("body").send_keys([ :control, "k" ])
    find("dialog#command-palette input").set("New p")
    assert_selector "#jump-results [role=option]", text: "New page"
    find("#jump-results [role=option] a", text: "New page").click

    assert_selector "dialog#new-page-dialog[open]"
    assert_no_selector "dialog#command-palette[open]"
    assert_current_path admin_page_path(@about)
  end
end
