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

    add_page_under(@services)

    assert_selector "dialog#new-page-dialog[open]"
    assert_equal @services.id.to_s, find("#new-page-inside").value
    assert_selector "dialog#new-page-dialog form#new-page-form"
    assert_eventually { page.evaluate_script("document.activeElement.id") == "new-page-title" }
    assert_selector "dialog#new-page-dialog [data-admin--editor--new-record-target=url]", text: "URL: /services/"

    fill_in "new-page-title", with: "Our Team"
    assert_selector "dialog#new-page-dialog [data-admin--editor--new-record-target=url]", text: "URL: /services/our-team"
    assert_selector "dialog#new-page-dialog [data-admin--editor--new-record-target=note]", text: "Created as a draft at the end of Services."

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

    add_page_under(@services)
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
    assert_eventually { page.evaluate_script("document.activeElement.classList.contains('admin-error-summary')") }
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
    assert_selector "dialog#new-post-dialog form#new-post-form"
    assert_eventually { page.evaluate_script("document.activeElement.id") == "new-post-title" }
    assert_selector "dialog#new-post-dialog [data-admin--editor--new-record-target=url]", text: "Not listed on any page yet"

    find("dialog#new-post-dialog label", text: ContentTypes.find("now_update").label).click
    fill_in "new-post-title", with: "Writing this down"
    click_button "Create draft"

    assert_selector "header.admin-editor-header", wait: 10
    created = Post.order(:id).last
    assert_equal "now_update", created.content_type
    assert_equal "Writing this down", created.title
    assert_current_path admin_post_path(created)
  end

  test "a form that fails to load shows a message with Try again, never an empty dialog" do
    visit admin_page_path(@about)
    await_admin_controllers
    good = page.evaluate_script("document.querySelector('[data-admin--editor--new-record-kind-value=page]').getAttribute('data-admin--editor--new-record-url-value')")
    page.execute_script("document.querySelector('[data-admin--editor--new-record-kind-value=page]').setAttribute('data-admin--editor--new-record-url-value', '/cs-studio/pages/does-not-exist')")

    # Review C, M15: the alert is empty until the failure happens (text that is
    # already in the page and merely un-hidden is not announced).
    assert_equal "", page.evaluate_script("document.querySelector('[data-admin--editor--new-record-target=failure] [role=alert]').textContent")
    click_link "+ New page"
    assert_selector "dialog#new-page-dialog [data-admin--editor--new-record-target=failure] [role=alert]", text: "The form couldn’t be loaded.", visible: :visible
    assert_button "Create page", disabled: true

    page.execute_script("document.querySelector('[data-admin--editor--new-record-kind-value=page]').setAttribute('data-admin--editor--new-record-url-value', #{good.to_json})")
    click_button "Try again"
    assert_selector "dialog#new-page-dialog form#new-page-form"
    assert_no_selector "[data-admin--editor--new-record-target=failure]", visible: :visible
    assert_button "Create page", disabled: false
  end

  test "the palette's New page and New post entries close it and open the dialogs" do
    visit admin_page_path(@about)
    await_admin_controllers

    find("body").send_keys([ :control, "k" ])
    find("dialog#command-palette input").set("New p")
    # The results FOR THIS QUERY, not the unfiltered list the palette opened
    # with -- it has a "New page" row too, so waiting for the row alone was
    # satisfied at once, and the click then raced the re-render: the list
    # shrank under the pointer and the click landed on the dialog's backdrop,
    # which closes the palette (seen in a looped run: `click DIALOG`, then
    # the render for "New p"). About one full-suite run in three.
    assert_selector "#jump-results [data-query='New p'] [role=option]", text: "New page"
    find("#jump-results [role=option] a", text: "New page").click

    assert_selector "dialog#new-page-dialog[open]"
    assert_no_selector "dialog#command-palette[open]"
    assert_current_path admin_page_path(@about)
  end

  test "a branch editor opens New page from the palette and creates a page in their branch" do
    branch = create_page(title: "Branch")
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "pages.create", scope: { "page_ids" => [ branch.id ] })
    Capybara.reset_sessions!
    sign_in_via_form(users(:editor_branch))
    visit admin_page_path(branch)
    await_admin_controllers

    find("body").send_keys([ :control, "k" ])
    find("dialog#command-palette input").set("New p")
    assert_selector "#jump-results [data-query='New p'] [role=option]", text: "New page" # see the test above
    find("#jump-results [role=option] a", text: "New page").click

    assert_selector "dialog#new-page-dialog[open] form#new-page-form"
    assert_equal branch.id.to_s, find("#new-page-inside").value
    fill_in "new-page-title", with: "Inside the branch"
    click_button "Create page"

    assert_selector "header.admin-editor-header", wait: 10
    assert_equal branch, Page.order(:id).last.parent
  end

  test "an expired session sends the user to sign-in instead of showing a load failure" do
    visit admin_page_path(@about)
    await_admin_controllers
    Session.delete_all

    click_link "+ New page"

    assert_selector "h1, form", text: /Sign in/i, wait: 10
    assert_current_path admin_sign_in_path
  end

  test "a submit that never reaches the server keeps the typed form and re-enables Create" do
    visit admin_page_path(@about)
    await_admin_controllers
    click_link "+ New page"
    assert_selector "dialog#new-page-dialog form#new-page-form"
    page.execute_script("const real = window.fetch; window.fetch = (url, options) => (options && options.method && options.method.toUpperCase() === 'POST') ? Promise.reject(new TypeError('offline')) : real(url, options)")

    fill_in "new-page-title", with: "Offline attempt"
    assert_equal "", page.evaluate_script("document.querySelector('[data-admin--editor--new-record-target=submitFailure]').textContent")
    click_button "Create page"

    assert_selector "[data-admin--editor--new-record-target=submitFailure]", text: "Couldn’t save.", visible: :visible
    assert_equal "Offline attempt", find("#new-page-title").value
    assert_button "Create page", disabled: false
    assert_no_selector "[data-admin--editor--new-record-target=failure]", visible: :visible
    # Turbo rethrows the failed submission's fetch, unhandled, after the
    # controller has shown its message; that is the failure this test provokes.
    expect_js_error(/TypeError: offline/, times: 2)
  end

  private

  # A row's "+" is drawn only while the pointer is over the row (or the link
  # has keyboard focus): Tailwind puts every `hover:` style inside
  # `@media (hover: hover)`, and the headless Chrome on the CI runner reports
  # a device that cannot hover, so there the link never becomes visible
  # however the pointer moves (it failed on every CI run and never locally).
  # The link is in the page and clickable either way -- only its opacity
  # differs -- so the click doesn't wait for visibility; the hover stays for
  # the browsers where it is what a person would do.
  def add_page_under(parent)
    link = find("li[data-page-id='#{parent.id}'] > div a[aria-label^='Add a page under']", visible: :all)
    link.hover
    link.click
  end
end
