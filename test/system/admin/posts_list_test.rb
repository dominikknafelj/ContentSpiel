require "application_system_test_case"

# The posts list in a real browser (design pass round 2, Task 17): ticking
# rows and the bulk bar (Publish, Move to trash with Undo), the filters that
# apply without a button, and the split New post button.
class Admin::PostsListSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    Current.set(actor: users(:one)) do
      @first = create_post(title: "First draft", published: false)
      @second = create_post(title: "Second draft", published: false)
      @third = create_post(title: "Third draft", published: false)
    end
    sign_in_via_form(users(:one))
  end

  # A scripted click, like `press`: the checkbox is a real input, this only
  # sidesteps headless Chrome's intermittent dropped native clicks.
  def tick(post) = find("#select-post-#{post.id}").execute_script("this.click()")

  test "select two drafts, Publish them, and both lose their Draft chip" do
    visit admin_posts_path
    await_admin_controllers
    assert_selector "tbody tr", count: 3
    assert_no_selector "[data-admin--bulk-select-target=bar]", visible: :visible

    tick(@first)
    tick(@second)
    assert_selector "[data-admin--bulk-select-target=bar]", text: "2 selected"
    assert_selector "thead input[data-admin--bulk-select-target=all]:indeterminate"

    within("[data-admin--bulk-select-target=bar]") { press "Publish" }
    assert_selector "#toasts .admin-toast", text: "Published 2 posts.", wait: 10
    assert @first.reload.live?
    assert @second.reload.live?
    assert_not @third.reload.live?
    assert_selector "tr#post_#{@third.id} .admin-status-chip", text: "Draft"
    assert_no_selector "tr#post_#{@first.id} .admin-status-chip"
    assert_no_selector "tr#post_#{@second.id} .admin-status-chip"
    assert_no_selector "[data-admin--bulk-select-target=bar]", visible: :visible
  end

  test "the header checkbox selects every row on the page and clears them again" do
    visit admin_posts_path
    await_admin_controllers
    find("#posts-select-all").execute_script("this.click()")
    assert_selector "[data-admin--bulk-select-target=bar]", text: "3 selected"
    find("#posts-select-all").execute_script("this.click()")
    assert_no_selector "[data-admin--bulk-select-target=bar]", visible: :visible

    tick(@first)
    assert_selector "[data-admin--bulk-select-target=bar]", text: "1 selected"
    within("[data-admin--bulk-select-target=bar]") { press "Clear" }
    assert_no_selector "[data-admin--bulk-select-target=bar]", visible: :visible
    assert_not find("#select-post-#{@first.id}").checked?
  end

  test "move one to the trash behind a confirmation that names the count, then Undo brings it back" do
    visit admin_posts_path
    await_admin_controllers
    tick(@third)
    within("[data-admin--bulk-select-target=bar]") { press "Move to trash" }
    within("dialog#bulk-trash-dialog[open]") do
      assert_text "1 post"
      press "Move to trash"
    end

    assert_selector "#toasts .admin-toast", text: "Moved 1 post to the trash.", wait: 10
    assert @third.reload.trashed?
    assert_no_selector "tr#post_#{@third.id}"

    within("#toasts") { press "Undo" }
    assert_selector "#toasts .admin-toast", text: "Restored 1 post.", wait: 10
    assert_not @third.reload.trashed?
    assert_selector "tr#post_#{@third.id}"
  end

  test "a row's Move to trash asks first, keeps the filter, and Undo restores it" do
    visit admin_posts_path(q: "draft")
    await_admin_controllers
    find("tr#post_#{@second.id} button[aria-label^='Actions for']").click
    find("tr#post_#{@second.id} [role=menu] button", text: "Move to trash").click
    within("dialog#bulk-trash-dialog[open]") do
      assert_text "This moves 1 post to the trash."
      press "Move to trash"
    end
    assert_selector "#toasts .admin-toast", text: "Moved 1 post to the trash.", wait: 10
    assert_current_path(/q=draft/)
    assert @second.reload.trashed?
    assert_not @first.reload.trashed?
    within("#toasts") { press "Undo" }
    assert_selector "#toasts .admin-toast", text: "Restored 1 post.", wait: 10
    assert_not @second.reload.trashed?
  end

  # Review C, I1 (the other call sites of the menu-opened dialog) and Task 17's
  # p3: a row's Move to trash replaces the selection with that one row; a
  # cancelled dialog puts the editor's own ticks back and focus returns to the
  # row's ⋯ button, not <body>.
  test "cancelling a row's Move to trash restores the previous selection and returns focus to the row's menu button" do
    visit admin_posts_path
    await_admin_controllers
    tick(@first)
    tick(@third)
    assert_selector "[data-admin--bulk-select-target=bar]", text: "2 selected"

    find("tr#post_#{@second.id} button[aria-label^='Actions for']").click
    find("tr#post_#{@second.id} [role=menu] button", text: "Move to trash").click
    within("dialog#bulk-trash-dialog[open]") do
      assert_text "This moves 1 post to the trash."
      press "Cancel"
    end
    assert_no_selector "dialog[open]"
    assert_selector "[data-admin--bulk-select-target=bar]", text: "2 selected"
    assert find("#select-post-#{@first.id}").checked?
    assert find("#select-post-#{@third.id}").checked?
    assert_not find("#select-post-#{@second.id}").checked?
    assert_selector "tr#post_#{@second.id} button[aria-label^='Actions for']:focus"
    assert_not @second.reload.trashed?
  end

  # Task 17's p1: connecting over boxes that are already ticked (a page
  # restored from Turbo's cache) is not a change the user made, so nothing is
  # announced; ticking one afterwards is.
  test "reconnecting over ticked rows announces nothing until the selection changes" do
    visit admin_posts_path
    await_admin_controllers
    status = "[data-admin--bulk-select-target=status]"

    page.execute_script(<<~JS)
      document.querySelector("#select-post-#{@first.id}").checked = true
      const root = document.querySelector("[data-controller~='admin--bulk-select']")
      window.__root = root
      window.__controllers = root.getAttribute("data-controller")
      root.setAttribute("data-controller", "")
    JS
    sleep 0.3 # Stimulus disconnects on the mutation, a task later
    page.execute_script("window.__root.setAttribute('data-controller', window.__controllers)")
    assert_selector "[data-admin--bulk-select-target=bar]", text: "1 selected"
    assert_equal "", find(status, visible: :all).text(:all)

    tick(@second)
    assert_selector status, text: "2 posts selected", visible: :all
  end

  test "the Translation filter narrows the list without a button" do
    with_locales(%w[en de], default: "en") do
      Translations::State.where(record_type: "Post").delete_all
      Translations::State.create!(record_type: "Post", record_id: @first.id, locale: "de", state: "outdated", outdated_count: 1)
      Translations::State.create!(record_type: "Post", record_id: @second.id, locale: "de", state: "complete")
    end
    visit admin_posts_path
    await_admin_controllers
    assert_selector "tbody tr", count: 3

    select "Outdated", from: "translation"
    assert_selector "tbody tr", count: 1, wait: 10
    assert_selector "tr#post_#{@first.id}"
    assert_current_path(/translation=outdated/)
  end

  test "the split button opens the New post dialog with the chosen type" do
    visit admin_posts_path
    await_admin_controllers

    find("button[aria-label='Choose another type of post']").click
    find("[role=menu] a", text: "New resume entry").click
    assert_selector "dialog#new-post-dialog[open]"
    assert_selector "dialog#new-post-dialog input[type=radio][value=resume_entry]:checked", visible: :all, wait: 10

    # The pick came from a menu item: Escape hands focus back to the caret.
    find("dialog#new-post-dialog").send_keys(:escape)
    assert_no_selector "dialog[open]"
    assert_selector "button[aria-label='Choose another type of post']:focus"
  end
end
