require "application_system_test_case"

# The dashboard in a browser: sign-in lands here, "New post…" makes a draft
# through the New post dialog, the draft shows up in "Pick up where you left
# off" as a tile, and once it is scheduled it shows up in "Publishing on its
# own" at its go-live time, in the site's time zone, not UTC.
class Admin::DashboardSystemTest < ApplicationSystemTestCase
  # The layout's New post dialog, opened from the dashboard: a type, a
  # title, and Create draft opens the new post's editor.
  def create_post_in_dialog(title)
    assert_selector "dialog#new-post-dialog[open] form#new-post-form"
    within("dialog#new-post-dialog") do
      select ContentTypes.find("blog").label, from: "Type"
      fill_in "new-post-title", with: title
      click_button "Create draft"
    end
    assert_selector "header.admin-editor-header", wait: 10
  end

  test "land on the dashboard, make a post with New post…, schedule it and see it go live next in local time" do
    site_settings(:default).update!(time_zone: "Europe/Berlin")
    sign_in_via_form(users(:one))
    assert_selector "h1", text: "Dashboard"
    await_admin_controllers

    press "New post…"
    create_post_in_dialog("From the dashboard")

    visit_screen admin_root_path
    within("section[aria-labelledby=dashboard-drafts]") { assert_selector "article.admin-draft-tile", text: "From the dashboard" }

    # Mobility stores `title` as jsonb, so a plain `where(title: ...)` would
    # compare jsonb to a string (CLAUDE.md's own warning) -- `.i18n` is the
    # query scope that actually looks inside the translated column, same as
    # `StarterContent` uses to find its own seeded posts by title.
    post = Post.kept.i18n.find_by!(title: "From the dashboard")
    post.update!(published_at: Time.find_zone("Europe/Berlin").local(2030, 7, 1, 9, 30))

    visit_screen admin_root_path
    within("section[aria-labelledby=dashboard-going-live-next]") do
      assert_text "From the dashboard"
      # 09:30 BERLIN time on 1 July -- the stored UTC instant is 07:30, so a
      # row drawn in UTC would say 07:30 here.
      assert_selector "time[title='1 Jul 2030, 09:30']"
    end
  end

  test "New post… opens the New post dialog, and its draft opens in the editor" do
    sign_in_via_form(users(:one))
    visit_screen admin_root_path

    within("div.admin-dashboard__head") { press "New post…" }
    assert_current_path admin_root_path
    create_post_in_dialog("Quick one")

    created = Post.order(:id).last
    assert_nil created.published_at
    assert_equal "Quick one", created.title
    assert_current_path admin_post_path(created)
  end

  test "the activity feed shows published after a draft is published" do
    post = Current.set(actor: users(:one), channel: :admin) { create_post(title: "To publish", published: false) }
    sign_in_via_form(users(:one))
    visit admin_post_path(post)
    find("header button.bg-accent", text: "Publish").click
    assert_text "Live", wait: 10

    visit admin_root_path
    within("section[aria-labelledby=dashboard-activity]") do
      assert_text "published “To publish”"
    end
  end

  # Something in every panel: a draft of the viewer's, a scheduled post, an
  # open thread that mentions the viewer (a row in Waiting for you and in
  # Notes for you) and a second language, so "Languages behind" is drawn.
  def fill_dashboard
    with_locales(%w[en de], default: "en")
    Current.set(actor: users(:one), channel: :admin) do
      create_post(title: "Half-written", published: false)
      create_post(title: "Later").update!(published_at: 2.days.from_now)
    end
    @pricing = create_page(title: "Pricing")
    block = @pricing.content_blocks.create!(block_type: "rich_text", position: 0)
    as(users(:two)) { Notes::Start.call(block, body: "Is this ready, @[#{users(:one).id}]?") }
    # A live page with an open thread and unpublished changes: one row with both reasons.
    Current.set(actor: users(:one), channel: :admin) do
      discussed = create_page(title: "Contact")
      discussed_block = discussed.content_blocks.create!(block_type: "rich_text", position: 0)
      assert Pages::Save.call(discussed, translations: { "en" => { title: "Contact us" } }).ok?
      @discussed = discussed
      @discussed_block = discussed_block
    end
    as(users(:two)) { Notes::Start.call(@discussed_block, body: "Phone number?") }
  end

  # The boxes of the dashboard, its main column and its rail, and the
  # computed looks the docked rules change, each beside the token it should
  # equal (read from a probe that uses the token, so the comparison is
  # between two computed values in this theme).
  def layout
    page.evaluate_script(<<~JS)
      (() => {
        const box = (element) => { const r = element.getBoundingClientRect(); return { left: r.left, right: r.right, top: r.top, bottom: r.bottom, width: r.width } }
        const probe = (declaration, property) => {
          const element = document.createElement("div")
          element.style.cssText = declaration
          document.body.append(element)
          const value = getComputedStyle(element)[property]
          element.remove()
          return value
        }
        const rail = document.querySelector(".admin-dashboard__rail")
        const panels = Array.from(rail.querySelectorAll(".admin-dashboard-panel"))
        const head = panels[0].querySelector(".admin-dashboard-panel__head")
        return {
          dashboard: box(document.querySelector(".admin-dashboard")),
          head: box(document.querySelector(".admin-dashboard__head")),
          main: box(document.querySelector(".admin-dashboard__main")),
          rail: box(rail),
          panel_tops: panels.map((panel) => panel.getBoundingClientRect().top),
          rail_background: getComputedStyle(rail).backgroundColor,
          rail_token: probe("background-color: var(--cs-rail)", "backgroundColor"),
          panel_shadows: panels.map((panel) => getComputedStyle(panel).boxShadow),
          shadow_1: probe("box-shadow: var(--cs-shadow-1)", "boxShadow"),
          head_background: getComputedStyle(head).backgroundColor,
          head_warm: probe("background-color: var(--cs-head-warm)", "backgroundColor")
        }
      })()
    JS
  end

  def docked?(boxes) = boxes["rail"]["left"] >= boxes["main"]["right"] && (boxes["rail"]["top"] - boxes["main"]["top"]).abs < 1

  test "at 1600px the information stands in a rail right of the main column, on the rail's ground without cards or bands" do
    fill_dashboard
    sign_in_via_form(users(:one))
    at_window(1600) do
      visit_screen admin_root_path
      boxes = layout
      assert docked?(boxes), boxes.inspect
      assert_in_delta boxes["main"]["right"] + 28, boxes["rail"]["left"], 1, "the rail stands --cs-rail-gap right of the main column"
      assert_in_delta 360, boxes["rail"]["width"], 1, "the rail is --cs-rail-width"
      assert_in_delta boxes["dashboard"]["left"], boxes["main"]["left"], 1, "the main column starts at the dashboard's left edge"
      assert_operator boxes["dashboard"]["width"], :<, 1680, "the window leaves the dashboard less than the content max"
      assert_in_delta boxes["dashboard"]["right"], boxes["rail"]["right"], 1, "the main column fills to the rail"
      assert_in_delta boxes["rail"]["right"], boxes["head"]["right"], 1, "the heading row ends where the rail does"
      assert_equal boxes["rail_token"], boxes["rail_background"]
      assert_equal 3, boxes["panel_shadows"].size, "Publishing on its own, Languages behind and What changed recently"
      assert_equal [ "none" ], boxes["panel_shadows"].uniq, "no card on the rail"
      assert_equal "rgba(0, 0, 0, 0)", boxes["head_background"], "no band on the rail"
    end
  end

  # The draft tiles' columns, counted from the computed grid.
  def tile_columns = page.evaluate_script("getComputedStyle(document.querySelector('.admin-draft-tiles')).gridTemplateColumns.split(' ').length")

  test "at 2400px the dashboard stops at the content max, centred, with four draft tiles a row" do
    fill_dashboard
    sign_in_via_form(users(:one))
    at_window(2400) do
      visit_screen admin_root_path
      boxes = layout
      assert docked?(boxes), boxes.inspect
      assert_in_delta 1680, boxes["rail"]["right"] - boxes["main"]["left"], 1, "the composition stops at the content max"
      assert_in_delta 1292, boxes["main"]["width"], 1
      assert_in_delta 360, boxes["rail"]["width"], 1
      left = boxes["main"]["left"] - boxes["dashboard"]["left"]
      right = boxes["dashboard"]["right"] - boxes["rail"]["right"]
      assert_operator left, :>, 150, "the premise: the window leaves spare width"
      assert_in_delta left, right, 1, "the spare width is split evenly either side"
      assert_in_delta boxes["main"]["left"], boxes["head"]["left"], 1, "the heading row starts with the composition"
      assert_in_delta boxes["rail"]["right"], boxes["head"]["right"], 1, "the heading row stops with the composition"
      assert_equal 4, tile_columns, "the tiles take four columns from 64rem of the main column"
    end
  end

  test "at 1100px the information follows the main column as cards with their warm heads" do
    fill_dashboard
    sign_in_via_form(users(:one))
    at_window(1100) do
      visit_screen admin_root_path
      boxes = layout
      assert_not docked?(boxes), boxes.inspect
      assert boxes["panel_tops"].all? { |top| top > boxes["main"]["bottom"] }, boxes.inspect
      assert_equal [ boxes["shadow_1"] ], boxes["panel_shadows"].uniq
      assert_equal boxes["head_warm"], boxes["head_background"]
    end
  end

  # Below 1280px the sidebar is a drawer and takes no width, so a 1279px
  # window gives the dashboard more room than a 1280px one. The widths are
  # asserted first: a change of the sidebar's width then fails here by name
  # rather than passing for another reason.
  test "the rail follows the dashboard's own width, not the window's" do
    fill_dashboard
    sign_in_via_form(users(:one))
    at_window(1279) do
      visit_screen admin_root_path
      boxes = layout
      assert_operator boxes["dashboard"]["width"], :>=, 1200
      assert docked?(boxes), boxes.inspect
    end
    at_window(1280) do
      visit_screen admin_root_path
      boxes = layout
      assert_operator boxes["dashboard"]["width"], :<, 1200
      assert_not docked?(boxes), boxes.inspect
    end
  end

  # Where the focus stands, by area: the heading row's link by its words,
  # a panel by its heading's id, and anything in the rail as "rail".
  def focus_area
    page.evaluate_script(<<~JS)
      (() => {
        const element = document.activeElement
        if (!element.closest(".admin-dashboard")) return null
        if (element.closest(".admin-dashboard__head")) return element.textContent.trim()
        if (element.closest(".admin-dashboard__rail")) return "rail"
        return element.closest("section[aria-labelledby]")?.getAttribute("aria-labelledby") ?? element.outerHTML
      })()
    JS
  end

  test "the focus goes heading, New page…, New post…, Waiting for you, Notes for you, drafts, then the rail" do
    fill_dashboard
    sign_in_via_form(users(:one))
    at_window(1600) do
      visit_screen admin_root_path
      # A press on the heading puts the sequential focus starting point there.
      find(".admin-dashboard__head h1").click
      areas = []
      60.times do
        page.driver.browser.keyboard.type(:tab)
        area = focus_area
        break if area.nil? && areas.any?
        areas << area unless area.nil? || areas.last == area
      end
      assert_equal [ "New page…", "New post…", "dashboard-waiting-title", "dashboard-notes-for-you", "dashboard-drafts", "rail" ], areas
    end
  end

  # The browser's own accessibility tree (CDP), for the first element the
  # selector finds: its computed name and description, and whether it is
  # left out of the tree (`ignored`).
  def accessibility(selector)
    cdp = page.driver.browser.page
    cdp.command("Accessibility.enable")
    object = cdp.command("Runtime.evaluate", expression: "document.querySelector(#{selector.to_json})")
    node = cdp.command("Accessibility.getPartialAXTree", objectId: object.dig("result", "objectId"), fetchRelatives: false).fetch("nodes").first
    { name: node.dig("name", "value"), description: node.dig("description", "value"), ignored: node["ignored"] }
  end

  # A row that presses as one is one link: its name is its title and its
  # reasons, its description its verb, and the marks and the verb drawn
  # beside it are left out of the tree, so nothing is announced twice.
  test "a waiting row and a draft tile are each announced once, with the title, the reason and the verb" do
    fill_dashboard
    sign_in_via_form(users(:one))
    visit_screen admin_root_path

    row = "turbo-frame#dashboard-waiting .admin-waiting-row:has(a[href*='/pages/#{@pricing.id}'])"
    assert_selector row, text: "Pricing"
    assert_equal({ name: "Pricing 1 open note", description: "Open thread", ignored: false }, accessibility("#{row} a.admin-waiting-row__link"))
    assert accessibility("#{row} .admin-row-verb")[:ignored], "the verb is the link's description, not read again as text"
    assert accessibility("#{row} [data-has-notes]")[:ignored], "the count is in the link's name, not read again"

    # A row with both reasons for someone who may publish: the chip's words
    # join the name, read through its hidden wrapper, and its verb is the
    # second link, so the name has no description.
    both = "turbo-frame#dashboard-waiting .admin-waiting-row:has(a[href*='/pages/#{@discussed.id}'])"
    assert_selector both, text: "Contact us"
    assert_equal({ name: "Contact us 1 open note Unpublished changes", description: nil, ignored: false }, accessibility("#{both} a.admin-waiting-row__link"))
    assert accessibility("#{both} [id$='-unpublished']")[:ignored], "the chip is in the link's name, not read again"

    tile = "section[aria-labelledby=dashboard-drafts] article.admin-draft-tile"
    assert_equal({ name: "Half-written", description: "Continue", ignored: false }, accessibility("#{tile} a.admin-draft-tile__link"))
    assert accessibility("#{tile} .admin-row-verb")[:ignored], "the verb is the link's description, not read again as text"
  end

  # The filter's three links stay inside Waiting for you's head at every
  # width the layout gives the panel: one column, two beside Notes for you,
  # docked and not.
  test "Waiting for you's filter fits its head at every window width" do
    fill_dashboard
    sign_in_via_form(users(:one))
    [ 390, 700, 900, 1100, 1279, 1280, 1400, 1600, 1900 ].each do |width|
      at_window(width) do
        visit_screen admin_root_path
        fit = page.evaluate_script(<<~JS)
          (() => {
            const head = document.querySelector("#dashboard-waiting .admin-dashboard-panel__head")
            const nav = head.querySelector("nav")
            const inner = head.getBoundingClientRect(), style = getComputedStyle(head)
            const right = inner.right - parseFloat(style.paddingRight)
            return { panel: inner.width, nav_right: nav.getBoundingClientRect().right, head_right: right,
                     clipped: Array.from(nav.querySelectorAll("a")).filter((link) => link.scrollWidth > link.clientWidth + 1).length,
                     overflow: nav.scrollWidth > nav.clientWidth + 1 }
          })()
        JS
        assert_operator fit["nav_right"], :<=, fit["head_right"] + 0.5, "at #{width}px: #{fit.inspect}"
        assert_equal 0, fit["clipped"], "at #{width}px: #{fit.inspect}"
        assert_not fit["overflow"], "at #{width}px: #{fit.inspect}"
      end
    end
  end

  # The frame's answer replaces the link that was pressed, so the focus
  # would fall to <body> and the next Tab start at the top of the document.
  test "a filter pressed from the keyboard leaves the focus on the filter it chose" do
    fill_dashboard
    sign_in_via_form(users(:one))
    visit_screen admin_root_path

    page.execute_script("document.querySelector('turbo-frame#dashboard-waiting nav a[href*=\"filter=unpublished\"]').focus()")
    page.driver.browser.keyboard.type(:enter)
    within("turbo-frame#dashboard-waiting") { assert_selector "nav a[aria-current=page]", text: "Unpublished changes" }
    focused = "(document.activeElement.matches('turbo-frame#dashboard-waiting nav a[aria-current=page]') && document.activeElement.textContent.trim())"
    assert_eventually(message: -> { "the focus is on #{page.evaluate_script('document.activeElement.outerHTML.slice(0, 200)')}" }) do
      page.evaluate_script(focused) == "Unpublished changes"
    end
  end

  # A restored snapshot would show the rows from before the person left (a
  # page just published, still offered for publishing), so Back to the
  # dashboard fetches it afresh.
  test "Back to the dashboard shows what waits now, not what waited when it was left" do
    fill_dashboard
    sign_in_via_form(users(:one))
    visit_screen admin_root_path
    within("section[aria-labelledby=dashboard-drafts]") { press "Half-written" }
    assert_selector "header.admin-editor-header", wait: 10

    create_post(title: "Changed meanwhile").update_columns(unpublished_changes_at: Time.current)
    page.go_back

    within("turbo-frame#dashboard-waiting") { assert_selector ".admin-waiting-row", text: "Changed meanwhile", wait: 8 }
  end

  test "Start a draft in an empty Pick up where you left off opens the New post dialog" do
    sign_in_via_form(users(:one))
    visit_screen admin_root_path

    within("section[aria-labelledby=dashboard-drafts]") { press "Start a draft" }
    assert_selector "dialog#new-post-dialog[open] form#new-post-form"
    assert_eventually { page.evaluate_script("document.activeElement.id") == "new-post-title" }
    assert_equal admin_root_path, URI(page.current_url).path
  end

  # The title's `::after` covers the tile, so a press anywhere on it, here
  # on the excerpt, is a press of the title's link.
  test "a draft tile is one target: a press on its excerpt opens the draft" do
    draft = Current.set(actor: users(:one), channel: :admin) { create_post(title: "Half-written", published: false) }
    draft.update_columns(excerpt: { Locales.default => "Where the story begins, and a little more." })
    sign_in_via_form(users(:one))
    visit_screen admin_root_path

    assert_selector "article.admin-draft-tile p.line-clamp-2", text: "Where the story begins"
    point = page.evaluate_script(<<~JS)
      (() => {
        const box = document.querySelector("article.admin-draft-tile p.line-clamp-2").getBoundingClientRect()
        const x = box.left + box.width / 2, y = box.top + box.height / 2
        return { x, y, href: document.elementFromPoint(x, y)?.closest("a")?.getAttribute("href") }
      })()
    JS
    assert_equal admin_post_path(draft), point["href"]
    # A real mouse press at the excerpt's middle: `press` would refuse it,
    # since the title's stretched link covers the excerpt, which is the point.
    page.driver.browser.mouse.click(x: point["x"], y: point["y"])

    assert_selector "header.admin-editor-header", wait: 10
    assert_current_path admin_post_path(draft)
  end
end
