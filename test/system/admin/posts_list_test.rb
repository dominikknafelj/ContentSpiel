require "application_system_test_case"

# The posts list in a real browser: ticking rows and the bulk bar (Publish,
# Move to trash with Undo), the filters that apply without a button and
# stand in the list's rail where the list has the room, and the split New
# post button.
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
  def tick(post) = find("#select-post-#{post.id}").click

  test "select two drafts, Publish them, and both lose their Draft chip" do
    visit_screen admin_posts_path
    assert_selector "tbody tr", count: 3
    assert_no_selector "[data-admin--posts--bulk-select-target=bar]", visible: :visible

    tick(@first)
    tick(@second)
    assert_selector "[data-admin--posts--bulk-select-target=bar]", text: "2 selected"
    assert_selector "thead input[data-admin--posts--bulk-select-target=all]:indeterminate"

    within("[data-admin--posts--bulk-select-target=bar]") { press "Publish" }
    assert_selector "#toasts .admin-toast", text: "Published 2 posts.", wait: 10
    assert @first.reload.live?
    assert @second.reload.live?
    assert_not @third.reload.live?
    assert_selector "tr#post_#{@third.id} .admin-status-chip", text: "Draft"
    assert_no_selector "tr#post_#{@first.id} .admin-status-chip"
    assert_no_selector "tr#post_#{@second.id} .admin-status-chip"
    assert_no_selector "[data-admin--posts--bulk-select-target=bar]", visible: :visible
  end

  test "the header checkbox selects every row on the page and clears them again" do
    visit_screen admin_posts_path
    find("#posts-select-all").click
    assert_selector "[data-admin--posts--bulk-select-target=bar]", text: "3 selected"
    find("#posts-select-all").click
    assert_no_selector "[data-admin--posts--bulk-select-target=bar]", visible: :visible

    tick(@first)
    assert_selector "[data-admin--posts--bulk-select-target=bar]", text: "1 selected"
    within("[data-admin--posts--bulk-select-target=bar]") { press "Clear" }
    assert_no_selector "[data-admin--posts--bulk-select-target=bar]", visible: :visible
    assert_not find("#select-post-#{@first.id}").checked?
  end

  test "move one to the trash behind a confirmation that names the count, then Undo brings it back" do
    visit_screen admin_posts_path
    tick(@third)
    within("[data-admin--posts--bulk-select-target=bar]") { press "Move to trash…" }
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
    visit_screen admin_posts_path(q: "draft")
    find("tr#post_#{@second.id} button[aria-label^='Actions for']").click
    find("tr#post_#{@second.id} [role=menu] button", text: "Move to trash…").click
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

  # A row's Move to trash replaces the selection with that one row; a
  # cancelled dialog puts the editor's own ticks back and focus returns to the
  # row's ⋯ button, not <body>.
  test "cancelling a row's Move to trash restores the previous selection and returns focus to the row's menu button" do
    visit_screen admin_posts_path
    tick(@first)
    tick(@third)
    assert_selector "[data-admin--posts--bulk-select-target=bar]", text: "2 selected"

    find("tr#post_#{@second.id} button[aria-label^='Actions for']").click
    find("tr#post_#{@second.id} [role=menu] button", text: "Move to trash…").click
    within("dialog#bulk-trash-dialog[open]") do
      assert_text "This moves 1 post to the trash."
      press "Cancel"
    end
    assert_no_selector "dialog[open]"
    assert_selector "[data-admin--posts--bulk-select-target=bar]", text: "2 selected"
    assert find("#select-post-#{@first.id}").checked?
    assert find("#select-post-#{@third.id}").checked?
    assert_not find("#select-post-#{@second.id}").checked?
    assert_selector "tr#post_#{@second.id} button[aria-label^='Actions for']:focus"
    assert_not @second.reload.trashed?
  end

  # Connecting over boxes that are already ticked (a page restored from
  # Turbo's cache) is not a change the user made, so nothing is announced;
  # ticking one afterwards is.
  test "reconnecting over ticked rows announces nothing until the selection changes" do
    visit_screen admin_posts_path
    status = "[data-admin--posts--bulk-select-target=status]"

    page.execute_script(<<~JS)
      document.querySelector("#select-post-#{@first.id}").checked = true
      const root = document.querySelector("[data-controller~='admin--posts--bulk-select']")
      window.__root = root
      window.__controllers = root.getAttribute("data-controller")
      root.setAttribute("data-controller", "")
    JS
    await_frames # Stimulus disconnects on the mutation, a task later
    page.execute_script("window.__root.setAttribute('data-controller', window.__controllers)")
    assert_selector "[data-admin--posts--bulk-select-target=bar]", text: "1 selected"
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
    visit_screen admin_posts_path
    assert_selector "tbody tr", count: 3

    select "Outdated", from: "Translation"
    assert_selector "tbody tr", count: 1, wait: 10
    assert_selector "tr#post_#{@first.id}"
    assert_current_path(/translation=outdated/)
  end

  # A row's open notes are a link into `#content` that opens the post with
  # its drawer open.
  test "a row's note count opens the post with its notes drawer open" do
    as(users(:two)) { Notes::Start.call(@second, body: "For @[#{users(:one).id}]: check the date") }
    visit_screen admin_posts_path

    assert_selector "tr#post_#{@second.id} a[data-notes-count][data-unread]", text: "1 new"
    assert_no_selector "tr#post_#{@first.id} [data-notes-count]"
    # The pill: 20px high, in accent for the person the note is addressed to.
    assert_equal 20, page.evaluate_script("Math.round(document.querySelector('tr#post_#{@second.id} a[data-notes-count]').getBoundingClientRect().height)")

    click_frame_link { find("tr#post_#{@second.id} a[data-notes-count]").click }

    assert_current_path(/\/posts\/#{@second.id}\?notes=open\z/)
    assert_selector "#notes-drawer #notes-list a[data-note-row]", text: "check the date"
  end

  test "the split button opens the New post dialog with the chosen type" do
    visit_screen admin_posts_path

    find("button[aria-label='Choose another type of post']").click
    find("[role=menu] a", text: "New post (Resume entry)").click
    assert_selector "dialog#new-post-dialog[open]"
    assert_selector "dialog#new-post-dialog select#new-post-type option[value=resume_entry]:checked", visible: :all, wait: 10

    # The pick came from a menu item: Escape hands focus back to the caret.
    find("dialog#new-post-dialog").send_keys(:escape)
    assert_no_selector "dialog[open]"
    assert_selector "button[aria-label='Choose another type of post']:focus"
  end

  # The chosen pill is the accent tint, so the accent ring stands 2px outside it.
  test "a selected pill reached with the keyboard is ringed in the accent 2px outside it, in both schemes" do
    visit_screen "/cs-studio/posts"
    %w[light dark].each do |scheme|
      page.execute_script("document.documentElement.dataset.theme = #{scheme.to_json}")
      find_field("Search titles").send_keys(:tab)
      ring, accent, offset = page.evaluate_script(<<~JS)
        (() => {
          const label = document.querySelector("label:has(#posts-scope-all)")
          const probe = document.createElement("span")
          probe.style.color = "var(--cs-accent)"
          document.body.append(probe)
          const colours = [ getComputedStyle(label).outlineColor, getComputedStyle(probe).color, getComputedStyle(label).outlineOffset ]
          probe.remove()
          return colours
        })()
      JS
      assert_equal accent, ring, scheme
      assert_equal "2px", offset, scheme
    end
  ensure
    page.execute_script("document.documentElement.dataset.theme = 'light'")
  end

  # The list rail's boxes, from the DOM: the list (the bulk-select wrapper
  # with the table), the filter panel, the bar, the heading row and the rail
  # container itself, with the panel's ground and the rail token's value
  # (read from a probe that uses the token, so both are computed values).
  def layout
    page.evaluate_script(<<~JS)
      (() => {
        const box = (element) => { const r = element.getBoundingClientRect(); return { left: r.left, right: r.right, top: r.top, bottom: r.bottom, width: r.width } }
        const probe = document.createElement("div")
        probe.style.backgroundColor = "var(--cs-rail)"
        document.body.append(probe)
        const token = getComputedStyle(probe).backgroundColor
        probe.remove()
        const panel = document.querySelector("form#posts-filters .admin-filter-panel")
        return {
          container: box(document.querySelector(".admin-list-rail")),
          head: box(document.querySelector(".admin-list-rail__head")),
          bar: box(document.querySelector("form#posts-filters .admin-filter-bar")),
          panel: box(panel),
          list: box(document.querySelector("[data-controller~='admin--posts--bulk-select']")),
          table: box(document.querySelector("[data-controller~='admin--posts--bulk-select'] table")),
          panel_background: getComputedStyle(panel).backgroundColor,
          rail_token: token
        }
      })()
    JS
  end

  # The legend's drawn width: Capybara counts a clipped, screen-reader-only
  # element as visible, so the box says whether it is shown.
  def legend_width = page.evaluate_script("document.querySelector('.admin-filter-panel legend').getBoundingClientRect().width")

  def docked?(boxes) = boxes["panel"]["left"] >= boxes["list"]["right"] && (boxes["panel"]["top"] - boxes["bar"]["top"]).abs < 1

  test "at 1600px the Type, Tag and Translation filters stand in a rail right of the list, on the rail's ground" do
    at_window(1600) do
      visit_screen admin_posts_path
      boxes = layout
      assert docked?(boxes), boxes.inspect
      assert_in_delta boxes["list"]["right"] + 28, boxes["panel"]["left"], 1, "the rail stands --cs-rail-gap right of the list"
      assert_in_delta 360, boxes["panel"]["width"], 1, "the rail is --cs-rail-width"
      assert_in_delta boxes["container"]["left"], boxes["list"]["left"], 1, "the list starts at the content's left edge"
      assert_in_delta boxes["bar"]["bottom"] + 16, boxes["list"]["top"], 1, "the rail's height goes to the list's row, not the bar's"
      assert_in_delta boxes["panel"]["right"], boxes["head"]["right"], 1, "the heading row ends where the rail does"
      assert_operator boxes["container"]["width"], :<, 1680, "the window leaves the list less than the content max"
      assert_in_delta boxes["container"]["right"], boxes["panel"]["right"], 1, "the list fills to the rail"
      assert_equal boxes["rail_token"], boxes["panel_background"]
      assert_operator legend_width, :>, 1, "the legend is shown on the rail"
    end
  end

  test "at 2400px the list stops at the content max, centred" do
    at_window(2400) do
      visit_screen admin_posts_path
      boxes = layout
      assert docked?(boxes), boxes.inspect
      assert_in_delta 1680, boxes["panel"]["right"] - boxes["list"]["left"], 1, "the composition stops at the content max"
      assert_in_delta 1292, boxes["list"]["width"], 1
      left = boxes["list"]["left"] - boxes["container"]["left"]
      right = boxes["container"]["right"] - boxes["panel"]["right"]
      assert_operator left, :>, 150, "the premise: the window leaves spare width"
      assert_in_delta left, right, 1, "the spare width is split evenly either side"
      assert_in_delta boxes["list"]["left"], boxes["head"]["left"], 1, "the heading row starts with the composition"
      assert_in_delta boxes["panel"]["right"], boxes["head"]["right"], 1, "the heading row stops with the composition"
    end
  end

  test "scrolled down a long list, the docked filters stay in view under the window's top" do
    30.times { |index| create_post(title: "Long list #{index}", published: false) }
    at_window(1600, height: 600) do
      visit_screen admin_posts_path
      assert docked?(layout), layout.inspect
      page.execute_script("window.scrollTo(0, document.documentElement.scrollHeight)")
      assert_eventually(message: "the list did not scroll") { page.evaluate_script("window.scrollY") > 300 }
      panel = layout["panel"]
      assert_in_delta 22, panel["top"], 1, "the rail sticks --cs-sp-4 under the window's top"
      assert_operator panel["bottom"], :<=, 600 - 22 + 1, "and ends inside the window"
    end
  end

  test "at 1100px the filters stand above the list, under the search and the segments" do
    at_window(1100) do
      visit_screen admin_posts_path
      boxes = layout
      assert_not docked?(boxes), boxes.inspect
      assert_operator boxes["panel"]["top"], :>=, boxes["bar"]["bottom"] - 0.5, boxes.inspect
      assert_operator boxes["panel"]["bottom"], :<=, boxes["table"]["top"] + 0.5, boxes.inspect
      assert_operator legend_width, :<=, 1, "the legend is for a screen reader only above the list"
      assert_selector ".admin-filter-panel label", text: "Type", visible: :visible
    end
  end

  # Below 1280px the sidebar is a drawer and takes no width, so a 1279px
  # window gives the list more room than a 1280px one. The widths are
  # asserted first: a change of the sidebar's width then fails here by name
  # rather than passing for another reason.
  test "the rail follows the list's own width: a 1279px window docks it, a 1280px one does not" do
    at_window(1279) do
      visit_screen admin_posts_path
      boxes = layout
      assert_operator boxes["container"]["width"], :>=, 1200
      assert docked?(boxes), boxes.inspect
    end
    at_window(1280) do
      visit_screen admin_posts_path
      boxes = layout
      assert_operator boxes["container"]["width"], :<, 1200
      assert_not docked?(boxes), boxes.inspect
    end
  end

  # Where the focus stands, by area: the heading row, the search, the
  # segments, a filter select by its id, and the list.
  def focus_area
    page.evaluate_script(<<~JS)
      (() => {
        const element = document.activeElement
        if (!element.closest(".admin-list-rail")) return null
        if (element.closest(".admin-list-rail__head")) return "New post"
        if (element.id === "q") return "search"
        if (element.closest(".admin-filter-bar fieldset")) return "segments"
        if (element.closest(".admin-filter-panel")) return element.id
        if (element.closest("[data-controller~='admin--posts--bulk-select']")) return "list"
        return element.outerHTML
      })()
    JS
  end

  test "the focus goes New post, search, the segments, the rail's Type, Tag and Translation, then the list, and a Type chosen from the keyboard keeps the focus on Type" do
    Current.set(actor: users(:one)) { create_post(title: "A resume entry", content_type: "resume_entry", published: false) }
    at_window(1600) do
      visit_screen admin_posts_path
      assert_selector "tbody tr", count: 4
      # A press on the heading puts the sequential focus starting point there.
      find(".admin-list-rail__head h1").click
      areas = []
      30.times do
        page.driver.browser.keyboard.type(:tab)
        area = focus_area
        break if area == "list"
        areas << area unless area.nil? || areas.last == area
      end
      assert_equal [ "New post", "search", "segments", "type", "tag", "translation" ], areas

      page.execute_script("document.getElementById('type').focus()")
      # Type-ahead: a letter chooses the first option it begins on every
      # platform, where an arrow key on macOS opens the picker instead.
      find("select#type").send_keys("b")
      assert_selector "tbody tr", count: 3, wait: 10
      assert_current_path(/type=blog/)
      assert_eventually(message: -> { "the focus is on #{page.evaluate_script('document.activeElement.outerHTML.slice(0, 200)')}" }) do
        page.evaluate_script("document.activeElement.id") == "type"
      end
      assert_no_selector "tbody tr", text: "A resume entry"
    end
  end
end
