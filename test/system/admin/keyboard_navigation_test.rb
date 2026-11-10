require "application_system_test_case"

# The keyboard of CS Studio's shared ways about a screen: the language tabs,
# the tab links, the pagination, a rail's panel and the theme switch, each a
# test its component's contract names (`keyboard:`,
# `docs/reference/design-system.md`, "Component contract"). A test sets where
# Tab starts by clicking words beside the control, and never focuses the
# control by script.
class Admin::KeyboardNavigationSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
  end

  test "the language tabs' links are Tab stops after the current language, and Enter on one opens that language, which becomes the current" do
    page_record = create_page(title: "About")
    visit_editor(page_record)

    tabs = "nav[aria-label='Languages']"
    find("#{tabs} [aria-current=true]", text: "English").click
    page.send_keys(:tab)
    assert_equal "Deutsch", focused_text
    page.send_keys(:enter)

    assert_selector "#{tabs} [aria-current=true]", text: "Deutsch"
    assert_current_path(/locale=de/)
    await_admin_controllers
  end

  test "a tab link is a Tab stop, and Enter on it goes to its tab, which the links mark current" do
    Current.set(actor: users(:one)) { Trash::Move.call(create_post(title: "Gone for now")) }
    visit_screen admin_trash_path

    tabs = "nav[aria-label='Filter by type']"
    assert_selector "#{tabs} a[aria-current=page]", text: "All"
    find("h1", text: "Trash").click
    stop_on("#{tabs} a[href*='type=posts']")
    click_frame_link { page.send_keys(:enter) }

    assert_selector "#{tabs} a[aria-current=page]", text: "Posts"
    assert_current_path(/type=posts/)
  end

  # Three posts at two a page: the posts list's own size is 50.
  test "the pagination's links are Tab stops, and Enter on Next goes to the next page, which it then says is current" do
    Current.set(actor: users(:one)) { %w[First Second Third].each { |title| create_post(title: "#{title} post") } }
    with_posts_per_page(2) do
      visit_screen admin_posts_path

      pagination = "nav[aria-label='Pagination']"
      assert_selector "#{pagination} [aria-current=page]", text: "1"
      find("#{pagination} p").click
      page.send_keys(:tab)
      assert_equal "2", focused_text
      page.send_keys(:tab)
      assert_equal "Next", focused_text
      click_frame_link { page.send_keys(:enter) }

      assert_selector "#{pagination} [aria-current=page]", text: "2"
      assert_selector "#{pagination} a[rel=prev]", text: "Previous"
    end
  end

  test "a rail's panel takes no focus of its own: Tab from its current tab goes to the first control inside it" do
    page_record = create_page(title: "Rail")
    at_window(1900) do
      visit_editor(page_record)
      assert_eventually(message: "the rail never docked") { page.evaluate_script("document.getElementById('editor-grid').hasAttribute('data-rail-docked')") }

      find("#editor-grid-tab-page").click
      page.send_keys(:tab)
      assert page.evaluate_script("document.getElementById('editor-grid-panel-page').contains(document.activeElement)"),
        "Tab from the Page tab did not go into its panel"
      assert_not page.evaluate_script("document.activeElement.id === 'editor-grid-panel-page'"), "the panel itself took the focus"
    end
  end

  test "the theme switch's choices are one Tab stop each, and Enter or Space on one chooses it and marks it checked" do
    visit_screen admin_root_path

    switch = "[role=radiogroup][aria-label='Theme']"
    # A press on Light chooses it and puts the focus there, where Tab starts.
    find("#{switch} [role=radio]", text: "Light").click
    assert_selector "#{switch} [role=radio][aria-checked=true]", text: "Light"
    page.send_keys(:tab)
    assert_equal "Dark", focused_text
    page.send_keys(:enter)
    assert_selector "#{switch} [role=radio][aria-checked=true]", text: "Dark"
    assert_equal "dark", page.evaluate_script("document.documentElement.dataset.themeChoice")

    page.send_keys(:tab)
    assert_equal "Auto", focused_text
    page.send_keys(:space)
    assert_selector "#{switch} [role=radio][aria-checked=true]", text: "Auto"
    assert_equal "auto", page.evaluate_script("document.documentElement.dataset.themeChoice")
  end

  private

  def focused_text = page.evaluate_script("document.activeElement.textContent.trim()")

  # Tab until `selector` holds the focus, from wherever Tab starts now, and
  # fail if it is not reached within `limit` stops.
  def stop_on(selector, limit: 40)
    limit.times do
      page.send_keys(:tab)
      return if page.evaluate_script("document.activeElement.matches(#{selector.to_json})")
    end
    flunk "Tab never reached #{selector}"
  end

  # The posts list's page size, for a list short enough to make: the server
  # runs in this process, so the controller reads the constant set here.
  def with_posts_per_page(size)
    original = Admin::PostsController::PER_PAGE
    silence_warnings { Admin::PostsController.const_set(:PER_PAGE, size) }
    yield
  ensure
    silence_warnings { Admin::PostsController.const_set(:PER_PAGE, original) }
  end
end
