require "application_system_test_case"

# The inbox in a browser: Notes for you and Waiting for you on the dashboard,
# the full list and the sidebar's count, where their rows lead, and what a
# live note fetches again.
class Admin::NoteInboxSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    users(:two).update!(name: "Dana")
    @me = users(:one)
    @page = create_page(title: "Pricing")
    @block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    sign_in_via_form(@me)
  end

  # "Open" is remembered in this browser, and the browser is shared with the
  # tests that follow: every notes system test forgets it again.
  teardown { page.execute_script("try { window.localStorage.removeItem('cs-notes-open') } catch (error) {}") }

  def mention(subject, body = "Is this ready, @[#{@me.id}]?") = as(users(:two)) { Notes::Start.call(subject, body: body) }.record

  # The accessible name the browser computes for the first element the
  # selector finds.
  def accessible_name(selector)
    cdp = page.driver.browser.page
    cdp.command("Accessibility.enable")
    object = cdp.command("Runtime.evaluate", expression: "document.querySelector(#{selector.to_json})")
    node = cdp.command("Accessibility.getPartialAXTree", objectId: object.dig("result", "objectId"), fetchRelatives: false)
    node.fetch("nodes").first.dig("name", "value")
  end

  def open_dashboard
    visit_screen "/cs-studio"
  end

  test "a row of Notes for you opens the page with its drawer at the thread, which reads it: the dot, the count and the badge go" do
    thread = mention(@block)
    open_dashboard

    assert_selector "#sidebar-badge-dashboard", text: "1"
    assert_selector "a[aria-label=\"Dashboard, 1 new\"] #sidebar-badge-dashboard"
    within "turbo-frame#notes-for-you" do
      assert_selector "[data-delivery][data-unread]", count: 1
      assert_selector "header", text: "1 new"
      assert_text "Page · Pricing · Rich text"
      press "Dana mentioned you"
    end

    # A whole editor visit and then the drawer's frame: more than the default wait on a busy machine.
    assert_current_path(/\/pages\/#{@page.id}\?notes=open&thread=#{thread.id}\z/, wait: 8)
    assert_selector "#notes-drawer #note-thread-#{thread.id}", text: "Is this ready", wait: 8
    assert_eventually(message: "opening the thread never marked its delivery read") { Notes::Delivery.unread.where(user: @me).none? }

    open_dashboard
    within "turbo-frame#notes-for-you" do
      assert_selector "[data-delivery]", count: 1
      assert_no_selector "[data-delivery][data-unread]"
      assert_no_selector "[data-notes-new]"
      assert_no_button "Mark all read"
    end
    assert_no_selector "#sidebar-badge-dashboard" # in the page, hidden and empty
    assert_selector "#sidebar-badge-dashboard[hidden]", visible: :all
  end

  test "an image's row opens the Media screen with the image chosen and the thread in its panel" do
    asset = create_media_asset
    thread = mention(asset, "Too dark, @[#{@me.id}]")
    open_dashboard

    within("turbo-frame#notes-for-you") { press "Dana mentioned you" }

    assert_current_path(/\/media\?selected=#{asset.id}&thread=#{thread.id}\z/)
    assert_selector "#media-rail #media-notes #note-thread-#{thread.id}", text: "Too dark"
    assert_eventually(message: "opening the thread never marked its delivery read") { Notes::Delivery.unread.where(user: @me).none? }
  end

  test "a row whose thread has since been deleted opens the page's notes with a sentence, not an error" do
    thread = mention(@page)
    kept = mention(@page, "Still here")
    open_dashboard
    assert_selector "turbo-frame#notes-for-you [data-delivery]", count: 1 # "Still here" mentions nobody
    as(users(:two)) { assert Notes::DeleteMessage.call(thread.first_message).ok? }

    find("turbo-frame#notes-for-you a[href$='thread=#{thread.id}']").click

    # The JavaScript error collector fails this test on "Content missing".
    assert_selector "#notes-drawer #notes-list [role=status]", text: "This note is gone"
    assert_selector "#notes-drawer a#note-row-#{kept.id}", text: "Still here"
  end

  test "Mark all read on the card stays on the dashboard and empties the badge" do
    mention(@page)
    mention(@block, "And this, @[#{@me.id}]")
    open_dashboard
    assert_selector "#sidebar-badge-dashboard", text: "2"
    assert_selector "a[aria-label=\"Dashboard, 2 new\"] #sidebar-badge-dashboard"

    within("turbo-frame#notes-for-you") { press "Mark all read" }

    assert_no_selector "turbo-frame#notes-for-you [data-delivery][data-unread]"
    assert_selector "turbo-frame#notes-for-you [data-delivery]", count: 2
    assert_current_path "/cs-studio"
    assert_no_selector "#sidebar-badge-dashboard"
    assert_equal 0, Notes::Delivery.unread.where(user: @me).count
  end

  test "a row of Notes for you is one link as wide as its card" do
    mention(@page)
    open_dashboard

    widths = page.evaluate_script("[ 'section', 'li > a[data-delivery]' ].map((selector) => document.querySelector('turbo-frame#notes-for-you ' + selector).getBoundingClientRect().width)")
    assert_in_delta widths[0], widths[1], 2
    assert_selector "turbo-frame#notes-for-you footer a", text: "All notes for you →"
  end

  test "Waiting for you lists a record once with its count in the neutral pill, and the whole row opens its notes" do
    mention(@page)
    mention(@block)
    open_dashboard

    within "turbo-frame#dashboard-waiting" do
      assert_selector "li", count: 1
      assert_selector "li .admin-notes-marker[data-has-notes]:not([data-unread])", text: "2"
      assert_selector "li .admin-waiting-row", text: /Page · Dana · /
      assert_selector "li .admin-row-verb", text: "Open thread"
      # The title's link is stretched over the row: as wide as the panel.
      widths = page.evaluate_script(<<~JS)
        [ "section", ".admin-waiting-row" ].map((selector) => document.querySelector("turbo-frame#dashboard-waiting " + selector).getBoundingClientRect().width)
          .concat([ (() => { const link = document.querySelector("turbo-frame#dashboard-waiting .admin-waiting-row__link"); return parseFloat(getComputedStyle(link, "::after").width) })() ])
      JS
      assert_in_delta widths[0], widths[1], 2
      assert_in_delta widths[1], widths[2], 2
      # The row presses as one: a press on it lands on the title's link.
      find("li .admin-waiting-row").click
    end

    # As above: a visit, then the drawer's frame.
    assert_current_path(/\/pages\/#{@page.id}\?notes=open\z/, wait: 8)
    assert_selector "#notes-drawer #notes-list a[data-note-row]", count: 2, wait: 8
  end

  test "a filter chosen in Waiting for you survives a live reload of the panel" do
    first = create_post(title: "First change")
    first.update_columns(unpublished_changes_at: Time.current)
    mention(@page, "Earlier, @[#{@me.id}]")
    open_dashboard
    await_notes_live

    within("turbo-frame#dashboard-waiting") { press "Unpublished changes" }
    within "turbo-frame#dashboard-waiting" do
      assert_selector "nav a[aria-current=page]", text: "Unpublished changes"
      assert_selector ".admin-waiting-row", count: 1, text: "First change"
    end

    # Nothing signals this one: only the reload the mention causes shows it.
    create_post(title: "Second change").update_columns(unpublished_changes_at: Time.current)
    mention(@block)

    assert_selector "turbo-frame#notes-for-you [data-delivery]", count: 2, wait: 8
    within "turbo-frame#dashboard-waiting" do
      assert_selector ".admin-waiting-row", text: "Second change", wait: 8
      assert_selector "nav a[aria-current=page]", text: "Unpublished changes"
      assert_selector ".admin-waiting-row", count: 2
      assert_no_selector ".admin-notes-marker"
    end
  end

  # Only a filter's press moves the focus to the filter; a reload a note
  # causes, here after a press, leaves it where the person put it.
  test "a live reload of Waiting for you leaves the focus where it is" do
    create_post(title: "First change").update_columns(unpublished_changes_at: Time.current)
    open_dashboard
    await_notes_live

    filter = "turbo-frame#dashboard-waiting nav a[href*='filter=unpublished']"
    page.execute_script("document.querySelector(#{filter.to_json}).focus()")
    page.driver.browser.keyboard.type(:enter)
    within("turbo-frame#dashboard-waiting") { assert_selector ".admin-waiting-row", count: 1, text: "First change" }
    # The answer's own link, current: the press's load has run.
    assert_eventually { page.evaluate_script("document.activeElement.matches(#{(filter + "[aria-current=page]").to_json})") }

    elsewhere = ".admin-dashboard__head a[href$='/posts/new']"
    page.execute_script("document.querySelector(#{elsewhere.to_json}).focus()")
    # The reload's `turbo:frame-load` comes after its rows are drawn.
    page.execute_script(<<~JS)
      window.waitingLoads = 0
      document.getElementById("dashboard-waiting").addEventListener("turbo:frame-load", () => window.waitingLoads++)
    JS
    create_post(title: "Second change").update_columns(unpublished_changes_at: Time.current)
    mention(@page)

    within("turbo-frame#dashboard-waiting") { assert_selector ".admin-waiting-row", text: "Second change", wait: 8 }
    await_js("window.waitingLoads > 0")
    assert page.evaluate_script("document.activeElement.matches(#{elsewhere.to_json})"),
      "the focus moved to #{page.evaluate_script('document.activeElement.outerHTML.slice(0, 200)')}"
  end

  test "a live note on a screen without the dashboard fetches no panel" do
    visit_screen admin_posts_path
    await_notes_live

    mention(@page)

    assert_selector "#sidebar-badge-dashboard", text: "1", wait: 8
    fetched = page.evaluate_script("performance.getEntriesByType('resource').map((entry) => entry.name)")
    assert fetched.any? { |name| name.include?("/notes/unread") }, "the count was fetched"
    # The panels' addresses, not a script's file (`controllers/admin/dashboard/waiting_controller-….js`).
    assert_empty fetched.grep(%r{/cs-studio/(dashboard/waiting|notes/card)(\?|\z)})
  end

  test "All notes for you is the same rows as a page, and its Mark all read stays there" do
    thread = mention(@page)
    open_dashboard

    # The footer's link, in words, not the head's arrow.
    within("turbo-frame#notes-for-you footer") { click_link "All notes for you" }

    assert_current_path "/cs-studio/notes"
    assert_selector "h1", text: "Notes for you"
    assert_selector "a[data-delivery][data-unread][href$='?notes=open&thread=#{thread.id}']", text: "Dana mentioned you"
    # The sidebar's Dashboard entry is not the current one here, and still counts.
    assert_selector "#sidebar-badge-dashboard", text: "1"

    press "Mark all read"

    assert_no_selector "[data-delivery][data-unread]"
    assert_selector "[data-delivery]", count: 1
    assert_current_path "/cs-studio/notes"
    assert_no_selector "#sidebar-badge-dashboard"
    assert_no_button "Mark all read"
  end

  # The avatar, the where line's chips and New are no controls: from the
  # row's link the keyboard goes to the next stop, and the link's words name
  # what they show.
  test "an inbox row is one Tab stop: its avatar, chips and New take no focus" do
    mention(@block)
    mention(@page, "And this, @[#{@me.id}]")
    visit_screen "/cs-studio/notes"
    assert_selector "[data-delivery]", count: 2

    assert_equal 0, page.evaluate_script("[ ...document.querySelectorAll('[data-delivery] *') ].filter((each) => each.tabIndex >= 0).length")
    assert_equal 2, page.evaluate_script("document.querySelectorAll('[data-delivery]').length")
    assert_selector "[data-delivery] [data-inbox-new]", count: 2
    first = "ul > li:first-child > a[data-delivery]"
    name = accessible_name(first)
    page.execute_script("window.__row = document.querySelector(#{first.to_json})")
    find(first).send_keys(:tab)
    assert_equal false, page.evaluate_script("document.activeElement === window.__row"), "the Tab did not leave the row's link"
    assert_equal false, page.evaluate_script("window.__row.contains(document.activeElement)"), "a Tab stop inside the row's link took the focus"
    assert_match(/\ADana mentioned you\b.*\bNew\b.*\bOpen thread\z/m, name)
  end

  test "Mentions narrows the list to mentions, its tab current, and a row still opens its thread" do
    mention(@page)
    resolved = mention(@block)
    as(users(:two)) { Notes::Resolve.call(resolved) }
    visit_screen "/cs-studio/notes"
    assert_selector "[data-delivery]", count: 2

    within("nav[aria-label=Show]") { click_link "Mentions" }

    assert_current_path "/cs-studio/notes?show=mentions"
    assert_selector "nav[aria-label=Show] a[aria-current=page]", text: /Mentions\s+1/
    assert_selector "[data-delivery]", count: 1
    assert_selector "[data-delivery]", text: "Dana mentioned you"
    assert_selector "[data-delivery]", text: "Page · Pricing"

    find("[data-delivery]").click

    assert_current_path(/\/pages\/#{@page.id}\?notes=open&thread=/, wait: 8)
  end

  # "New" is on its own line of the end column, under the time and over the
  # verb, so the verb alone sets the column's width: an unread row's words
  # keep the room of a read row's, in the full list and in the dashboard's
  # narrow panel at a 390px window.
  test "an unread row's sentence is as wide as a read row's, in the list and in the dashboard's panel at 390px" do
    original = page.current_window.size
    mention(@page)
    read = mention(@block, "Read, @[#{@me.id}]")
    Notes::Delivery.where(user: @me, thread: read).update_all(read_at: Time.current) # version: none (a test's own setup)
    page.current_window.resize_to(390, 900)
    widths = <<~JS
      [ ...document.querySelectorAll("[data-delivery]") ].map((row) => [ row.matches("[data-unread]"), row.querySelector("[data-inbox-sentence]").getBoundingClientRect().width ])
    JS

    visit_screen "/cs-studio/notes"
    assert_selector "[data-delivery]", count: 2
    list = page.evaluate_script(widths).to_h
    assert_equal 2, list.size, "one unread row and one read row"
    assert_in_delta list[true], list[false], 1

    visit_screen "/cs-studio"
    assert_selector "turbo-frame#notes-for-you [data-delivery]", count: 2
    panel = page.evaluate_script(widths).to_h
    assert_in_delta panel[true], panel[false], 1
    verb = page.evaluate_script("document.querySelector('turbo-frame#notes-for-you [data-delivery] .admin-row-verb').getBoundingClientRect().width")
    assert_operator verb, :<, 100
  ensure
    page.current_window.resize_to(*original)
  end

  # Where the screen's boxes are: the list's card, the rail of open threads
  # and the rail's computed margin, read in the browser.
  def rail_layout
    page.evaluate_script(<<~JS)
      (() => {
        const box = (element) => { const r = element.getBoundingClientRect(); return { left: r.left, right: r.right, top: r.top, bottom: r.bottom, width: r.width } }
        const rail = document.querySelector(".admin-notes-threads")
        return { list: box(document.querySelector("[data-delivery]").closest("ul").parentElement), rail: box(rail), margin_top: getComputedStyle(rail).marginTop }
      })()
    JS
  end

  test "the rail of open threads docks beside the list from 1200px of the list's width, and falls after it below" do
    original = page.current_window.size
    mention(@page)
    mention(@block, "Another thread, @[#{@me.id}]")

    page.current_window.resize_to(1600, 1000)
    visit_screen "/cs-studio/notes"
    assert_selector ".admin-notes-threads li a", text: "Pricing"
    boxes = rail_layout
    assert_operator boxes["rail"]["left"], :>=, boxes["list"]["right"], boxes.inspect
    assert_operator boxes["rail"]["top"], :<, boxes["list"]["top"], "the rail starts at the grid's top, beside the filter and the list"
    assert_equal "0px", boxes["margin_top"]
    assert_in_delta 360, boxes["rail"]["width"], 1

    page.current_window.resize_to(1100, 1000)
    visit_screen "/cs-studio/notes"
    assert_selector ".admin-notes-threads li a", text: "Pricing"
    boxes = rail_layout
    assert_operator boxes["rail"]["top"], :>=, boxes["list"]["bottom"], boxes.inspect
    assert_in_delta boxes["list"]["left"], boxes["rail"]["left"], 1
    assert_equal "16px", boxes["margin_top"]
    assert_in_delta boxes["list"]["width"], boxes["rail"]["width"], 1

    # A row of the rail opens the record's notes, as every link into a record's notes does.
    find(".admin-notes-threads li a", text: "Pricing").click
    assert_current_path(/\/pages\/#{@page.id}\?notes=open\z/, wait: 8)
  ensure
    page.current_window.resize_to(*original)
  end
end
