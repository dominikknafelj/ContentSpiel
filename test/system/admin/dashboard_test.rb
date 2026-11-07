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
      find("label", text: ContentTypes.find("blog").label).click
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

  # The panels' grid: three columns at most, by the dashboard's own width.
  # Five panels (two languages, so "Languages behind" is drawn) stand in two
  # rows of three columns.
  def card_grid
    page.evaluate_script(<<~JS)
      (() => {
        const grid = document.querySelector(".admin-dashboard-cards")
        const cards = Array.from(grid.querySelectorAll(":scope > section, :scope > turbo-frame > section"))
        return { columns: getComputedStyle(grid).gridTemplateColumns.split(" ").length, cards: cards.length,
                 rows: new Set(cards.map((card) => Math.round(card.getBoundingClientRect().top))).size }
      })()
    JS
  end

  test "the panels stand three in a row at 1600px and at 1400px, in two rows, and one in a row at 600px" do
    with_locales(%w[en de], default: "en")
    create_post(title: "Untranslated")
    sign_in_via_form(users(:one))
    begin
      [ [ 1600, 3, 2 ], [ 1400, 3, 2 ], [ 600, 1, 5 ] ].each do |width, columns, rows|
        page.driver.resize(width, 1000)
        visit admin_root_path
        await_admin_controllers
        assert_equal({ "columns" => columns, "cards" => 5, "rows" => rows }, card_grid, "at #{width}px")
      end
    ensure
      page.driver.resize(1400, 1400)
    end
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
