require "application_system_test_case"

# The Tags list in a real browser: the inline rename, the post count that
# opens the filtered posts list, the detail rail a row's Details opens (the
# tag's posts, Merge into… and Delete tag…), where it stands at each width,
# and the Merge and Delete dialogs -- one of each in the page, filled from
# the trigger that opened it.
class Admin::TagsSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    Current.set(actor: users(:one)) do
      create_post(title: "First", tags: [ "news" ])
      create_post(title: "Second", tags: [ "news", "studio" ])
      create_post(title: "Third", tags: [ "studio", "gear" ])
    end
    @news, @studio, @gear = %w[news studio gear].map { |name| Tag.find_by!(name: name) }
    sign_in_via_form(users(:one))
  end

  def row(tag) = "tr#tag_#{tag.id}"

  def details_link(tag) = "#{row(tag)} a[data-tag-details]"

  # Presses the row's Details and waits for the tag's detail in the rail.
  def details(tag)
    find(details_link(tag)).click
    assert_selector "#tag-detail-#{tag.id}", wait: 8
  end

  def rail_button(tag, label)
    find("#tag-detail-#{tag.id} button", text: label).click
  end

  # The focused element: its id, its name (an icon button's label, else its text) and whether it is a row's Details.
  def active
    page.evaluate_script(<<~JS)
      (() => {
        const element = document.activeElement
        return { id: element.id, name: element.getAttribute("aria-label") || element.textContent.trim(), details: element.hasAttribute("data-tag-details") }
      })()
    JS
  end

  test "clicking a name renames it in place and saves" do
    visit_screen admin_tags_path
    field = find("#tag-#{@gear.id}-name")
    field.set("kit")

    assert_selector "#tag-#{@gear.id}-save-status", text: /SAVED( · NOT PUBLISHED)? \d{2}:\d{2}/, wait: 8
    assert_eventually { @gear.reload.name == "kit" }
  end

  test "a duplicate name shows its error on the row and keeps the name it had" do
    visit_screen admin_tags_path
    field = find("#tag-#{@gear.id}-name")
    field.set("news")

    assert_selector "#tag-#{@gear.id}-name-errors", text: "has already been taken", wait: 8
    assert_equal "gear", @gear.reload.name
  end

  test "the post count opens the posts list filtered by that tag" do
    visit_screen admin_tags_path
    find("#{row(@news)} a", text: "2 posts").click

    assert_current_path(/\/posts\?tag=news/)
    assert_selector "tbody th a", text: "First"
    assert_selector "tbody th a", text: "Second"
    assert_no_selector "tbody th a", text: "Third"
  end

  test "Merge into… picks a target, never offers the tag itself, and moves the posts" do
    visit_screen admin_tags_path
    details(@news)
    rail_button(@news, "Merge into…")

    within("dialog#merge-tag-dialog[open]") do
      assert_selector "h2", text: "Merge “news” into…"
      assert_text "Its 2 posts get the chosen tag and “news” is deleted. This can't be undone."
      assert_button "Merge tags", disabled: true

      find("#merge-tag-into").send_keys("s")
      assert_selector "#merge-tag-into-listbox [role=option]", text: "studio"
      assert_no_selector "#merge-tag-into-listbox [role=option]", text: "news"
      find("#merge-tag-into-listbox [role=option]", text: "studio").click

      assert_selector "li[data-chip-value='studio']"
      assert_button "Merge tags", disabled: false
      click_button "Merge tags"
    end

    assert_selector "#toasts .admin-toast", text: "Merged “news” into “studio”", wait: 10
    assert_no_selector row(@news)
    assert_selector "#{row(@studio)} a", text: "3 posts"
    assert_not Tag.exists?(@news.id)
  end

  test "the one Merge dialog is refilled for each row, with nothing left from the last opening" do
    visit_screen admin_tags_path
    details(@news)
    rail_button(@news, "Merge into…")
    within("dialog#merge-tag-dialog[open]") do
      find("#merge-tag-into").send_keys("s")
      find("#merge-tag-into-listbox [role=option]", text: "studio").click
      assert_button "Merge tags", disabled: false
      click_button "Cancel"
    end
    assert_no_selector "dialog[open]"

    details(@gear)
    rail_button(@gear, "Merge into…")
    within("dialog#merge-tag-dialog[open]") do
      assert_selector "h2", text: "Merge “gear” into…"
      assert_text "Its 1 post gets the chosen tag"
      assert_no_selector "li[data-chip-value]"
      assert_button "Merge tags", disabled: true
    end
    assert_selector "dialog#merge-tag-dialog", count: 1, visible: :all
  end

  test "Delete tag… asks first, says how many posts are affected, and removes the row" do
    visit_screen admin_tags_path
    details(@gear)
    rail_button(@gear, "Delete tag…")

    within("dialog#delete-tag-dialog[open]") do
      assert_selector "h2", text: "Delete “gear”?"
      assert_text "It is removed from 1 post. The posts themselves stay."
      click_button "Delete tag"
    end

    assert_selector "#toasts .admin-toast", text: "Deleted “gear”", wait: 10
    assert_no_selector row(@gear)
    assert_no_selector "dialog[open]"
    assert_not Tag.exists?(@gear.id)
  end

  # The dialogs name the tag as it is called now, read from the row's input.
  test "after an inline rename the dialogs name the tag by its new name, and the picker excludes it" do
    visit_screen admin_tags_path
    details(@gear)
    find("#tag-#{@gear.id}-name").set("kit")
    assert_selector "#tag-#{@gear.id}-save-status", text: /SAVED( · NOT PUBLISHED)? \d{2}:\d{2}/, wait: 8

    rail_button(@gear, "Delete tag…")
    within("dialog#delete-tag-dialog[open]") do
      assert_selector "h2", text: "Delete “kit”?"
      click_button "Cancel"
    end

    rail_button(@gear, "Merge into…")
    within("dialog#merge-tag-dialog[open]") do
      assert_selector "h2", text: "Merge “kit” into…"
      find("#merge-tag-into").send_keys("k")
      assert_no_selector "#merge-tag-into-listbox [role=option]", text: "kit", wait: 1
    end
  end

  # A refusal has no body to render: the dialog would stay open over a
  # button that does nothing.
  test "a delete the server refuses closes the dialog and says so" do
    visit_screen admin_tags_path
    details(@gear)
    rail_button(@gear, "Delete tag…")
    assert_selector "dialog#delete-tag-dialog[open]"
    @gear.destroy!
    within("dialog#delete-tag-dialog[open]") { click_button "Delete tag" }

    assert_no_selector "dialog[open]"
    assert_selector "#toasts [role=alert]", text: "The tag wasn't deleted. Reload the list and try again."
  end

  # No visit: a `turbo:visit` listener installed before the deletes sets a
  # flag, which stays unset when the answer alone draws the empty state.
  test "deleting the chosen tag from the rail empties the rail and focuses a neighbour; deleting the last one shows the empty state from the answer, with no visit" do
    at_window(1600) do
      visit_screen admin_tags_path
      page.execute_script("window.__tagsVisit = undefined; document.addEventListener('turbo:visit', () => { window.__tagsVisit = true })")
      rows = page.all("table.admin-tags-table tbody tr").map { |tr| tr[:id] }
      first = Tag.find(rows.first.delete_prefix("tag_"))
      details(first)
      rail_button(first, "Delete tag…")
      within("dialog#delete-tag-dialog[open]") { click_button "Delete tag" }
      assert_no_selector row(first)
      assert_selector ".admin-tag-detail #tag-detail-empty"
      assert_no_selector "#tag-detail-#{first.id}"
      assert_eventually(message: "focus fell to the body") { page.evaluate_script("document.activeElement.id") == "tag-#{rows.second.delete_prefix('tag_')}-name" }

      rows.drop(1).each do |id|
        tag = Tag.find(id.delete_prefix("tag_"))
        details(tag)
        rail_button(tag, "Delete tag…")
        within("dialog#delete-tag-dialog[open]") { click_button "Delete tag" }
        assert_no_selector row(tag)
      end
      assert_text "No tags yet"
      assert_no_selector "table.admin-tags-table"
      # The rail holds its empty line, and with no tag left it takes no room.
      assert_selector "#tag-detail-empty", visible: :all
      assert_nil page.evaluate_script("window.__tagsVisit"), "the empty state was drawn by a visit, not by the answer"
    end
  end

  # The rail's boxes, from the DOM: the list rail container, the heading
  # row, the rail and the list, with the rail's ground and display and the
  # rail token's value (read from a probe that uses the token, so both are
  # computed values).
  def layout
    page.evaluate_script(<<~JS)
      (() => {
        const box = (element) => { const r = element.getBoundingClientRect(); return { left: r.left, right: r.right, top: r.top, bottom: r.bottom, width: r.width } }
        const probe = document.createElement("div")
        probe.style.backgroundColor = "var(--cs-rail)"
        document.body.append(probe)
        const token = getComputedStyle(probe).backgroundColor
        probe.style.backgroundColor = "var(--cs-surface)"
        const surface = getComputedStyle(probe).backgroundColor
        probe.remove()
        const rail = document.querySelector(".admin-tag-detail")
        return {
          container: box(document.querySelector(".admin-list-rail")),
          head: box(document.querySelector(".admin-list-rail__head")),
          rail: box(rail),
          list: box(document.querySelector("#tags-list")),
          rail_background: getComputedStyle(rail).backgroundColor,
          rail_display: getComputedStyle(rail).display,
          rail_token: token,
          surface_token: surface
        }
      })()
    JS
  end

  def docked?(boxes) = boxes["rail"]["width"] > 0 && boxes["rail"]["left"] >= boxes["list"]["right"] && (boxes["rail"]["top"] - boxes["list"]["top"]).abs < 1

  test "at 1600px a tag's details stand in a rail right of the list, on the rail's ground" do
    at_window(1600) do
      visit_screen admin_tags_path
      assert docked?(layout), layout.inspect
      assert_selector ".admin-tag-detail #tag-detail-empty", text: "Choose a tag to see its posts, merge it or delete it."

      details(@news)
      boxes = layout
      assert docked?(boxes), boxes.inspect
      assert_in_delta boxes["list"]["right"] + 28, boxes["rail"]["left"], 1, "the rail stands --cs-rail-gap right of the list"
      assert_in_delta 360, boxes["rail"]["width"], 1, "the rail is --cs-rail-width"
      assert_in_delta boxes["container"]["left"], boxes["list"]["left"], 1, "the list starts at the content's left edge"
      assert_in_delta boxes["rail"]["right"], boxes["head"]["right"], 1, "the heading row ends where the rail does"
      assert_equal boxes["rail_token"], boxes["rail_background"]
    end
  end

  test "at 1100px the details stand above the list as a card, and nothing stands there before a tag is chosen" do
    at_window(1100) do
      visit_screen admin_tags_path
      boxes = layout
      assert_equal "none", boxes["rail_display"], "an unchosen rail takes no room"
      assert_in_delta boxes["head"]["bottom"] + 16, boxes["list"]["top"], 1, boxes.inspect

      details(@news)
      boxes = layout
      assert_not docked?(boxes), boxes.inspect
      assert_operator boxes["rail"]["bottom"], :<=, boxes["list"]["top"], boxes.inspect
      assert_in_delta boxes["list"]["left"], boxes["rail"]["left"], 1
      assert_in_delta boxes["list"]["width"], boxes["rail"]["width"], 1
      assert_equal boxes["surface_token"], boxes["rail_background"], "below the threshold the detail is a card"
    end
  end

  # Below 1280px the sidebar is a drawer and takes no width, so a 1279px
  # window gives the list more room than a 1280px one. The widths are
  # asserted first: a change of the sidebar's width then fails here by name
  # rather than passing for another reason.
  test "the rail follows the list's own width: a 1279px window docks it, a 1280px one does not" do
    at_window(1279) do
      visit_screen admin_tags_path
      details(@news)
      boxes = layout
      assert_operator boxes["container"]["width"], :>=, 1200
      assert docked?(boxes), boxes.inspect
    end
    at_window(1280) do
      visit_screen admin_tags_path
      details(@news)
      boxes = layout
      assert_operator boxes["container"]["width"], :<, 1200
      assert_not docked?(boxes), boxes.inspect
    end
  end

  test "Details moves the focus to the tag's name in the rail, Tab goes through its posts and buttons, and Close and Escape give it back to the row's Details" do
    Current.set(actor: users(:one)) { 8.times { |n| create_post(title: "More news #{n}", tags: [ "news" ]) } }
    keyboard = page.driver.browser.keyboard
    at_window(1600) do
      visit_screen admin_tags_path
      second = Tag.find(page.all("table.admin-tags-table tbody tr")[1][:id].delete_prefix("tag_"))
      assert_equal @news, second, "tags are listed by name: gear, news, studio"
      titles = second.posts.kept.order(updated_at: :desc, id: :desc).first(8).map { |post| post.title(locale: :en) }

      [ :close, :escape ].each do |way|
        page.execute_script("document.querySelector(#{details_link(second).to_json}).focus()")
        keyboard.type(:enter)
        assert_selector "#tag-detail-#{second.id}", wait: 8
        assert_eventually(message: -> { "the focus is on #{active.inspect}" }) { active["id"] == "tag-detail-#{second.id}-name" }
        assert_selector "#{details_link(second)}[aria-current=true]"
        assert_selector "#{row(second)}[data-selected]"

        stops = Array.new(titles.size + 4) do
          keyboard.type(:tab)
          active["name"]
        end
        assert_equal [ *titles, "Show all 10 posts", "Merge into…", "Delete tag…", "Close" ], stops

        keyboard.type(way == :close ? :enter : :escape)
        assert_eventually(message: -> { "the focus is on #{active.inspect}" }) { active["details"] && active["name"] == "Details of “news”" }
        assert_no_selector "[data-tag-details][aria-current]"
        assert_no_selector "tr[data-selected]"
        assert_selector ".admin-tag-detail #tag-detail-empty"
      end
    end
  end

  # `admin--tags--dialogs` reads the pressed trigger's `data-tag-*` when a
  # dialog opens and keeps no reference to a trigger, so it never reads one
  # the rename's stream replaced.
  test "a rename of the chosen tag rewords the rail: its heading, Show all's address and both dialogs" do
    Current.set(actor: users(:one)) { 8.times { |n| create_post(title: "More gear #{n}", tags: [ "gear" ]) } }
    visit_screen admin_tags_path
    details(@gear)
    assert_selector "#tag-detail-#{@gear.id} a[data-tag-detail-show-all][href$='tag=gear']"

    find("#tag-#{@gear.id}-name").set("kit")
    assert_selector "#tag-#{@gear.id}-save-status", text: /SAVED( · NOT PUBLISHED)? \d{2}:\d{2}/, wait: 8
    assert_selector "#tag-detail-#{@gear.id}-name", text: "kit"
    assert_selector "#tag-detail-#{@gear.id} a[data-tag-detail-show-all][href$='tag=kit']"

    rail_button(@gear, "Merge into…")
    within("dialog#merge-tag-dialog[open]") do
      assert_selector "h2", text: "Merge “kit” into…"
      find("#merge-tag-into").send_keys("k")
      assert_no_selector "#merge-tag-into-listbox [role=option]", text: "kit", wait: 1
      click_button "Cancel"
    end
    assert_no_selector "dialog[open]"

    rail_button(@gear, "Delete tag…")
    within("dialog#delete-tag-dialog[open]") { assert_selector "h2", text: "Delete “kit”?" }
  end

  # The press blurs the input, whose `focusout` sends the save, and the
  # frame's GET goes out beside it: `admin--tags--detail#hold` keeps the GET
  # until this tab's writes are done, so it reads the committed name. Two of
  # this tab's requests are slowed to force the losing order every time
  # (every other request is handed to the real `fetch` untouched): the
  # row's PATCH waits 300ms before it is sent, and the detail's GET answer
  # waits 900ms after it arrived. Without the hold the GET is read before
  # the rename, the rename's answer finds no detail to replace, and the
  # GET's answer then draws the name the tag had.
  test "a Details pressed while its tag's rename is still saving draws the new name" do
    Current.set(actor: users(:one)) { 8.times { |n| create_post(title: "More gear #{n}", tags: [ "gear" ]) } }
    visit_screen admin_tags_path
    page.execute_script(<<~JS, "/cs-studio/tags/#{@gear.id}")
      const path = arguments[0]
      const real = window.fetch
      const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms))
      window.fetch = (input, init = {}) => {
        const url = new URL(typeof input === "string" ? input : input.url, location.href)
        if (url.pathname !== path) return real(input, init)
        const method = (init.method || "GET").toUpperCase()
        if (method === "PATCH") return wait(300).then(() => real(input, init))
        if (method === "GET") return real(input, init).then((response) => wait(900).then(() => response))
        return real(input, init)
      }
    JS
    find("#tag-#{@gear.id}-name").set("kit")
    find(details_link(@gear)).click

    assert_selector "#tag-detail-#{@gear.id}-name", text: "kit", wait: 8
    assert_selector "#tag-detail-#{@gear.id} a[data-tag-detail-show-all][href$='tag=kit']"
    assert_selector "#tag-#{@gear.id}-save-status", text: /SAVED( · NOT PUBLISHED)? \d{2}:\d{2}/, wait: 8
    assert_selector "#tag-#{@gear.id}-details[aria-label='Details of “kit”'][aria-current=true]"
  end

  def rail_display = page.evaluate_script("getComputedStyle(document.querySelector('.admin-tag-detail')).display")

  test "with no tags the rail takes no room, docked or not, and deleting the last tag takes it away" do
    Tag.destroy_all
    [ 1600, 1100 ].each do |width|
      at_window(width) do
        visit_screen admin_tags_path
        assert_text "No tags yet"
        assert_equal "none", rail_display, "no tag at #{width}px"
      end
    end

    tag = Tag.create!(name: "gear")
    at_window(1600) do
      visit_screen admin_tags_path
      assert_equal "block", rail_display, "a tag to choose: the docked rail shows its empty line"
      details(tag)
      rail_button(tag, "Delete tag…")
      within("dialog#delete-tag-dialog[open]") { click_button "Delete tag" }
      assert_text "No tags yet"
      assert_eventually(message: "the rail stayed after the last delete") { rail_display == "none" }
    end
  end

  test "a 50-character tag name and long post titles stay inside the rail" do
    long = "a" * 50
    Current.set(actor: users(:one)) do
      3.times { |n| create_post(title: "A very long post title that goes on and on past any rail's width, number #{n}", tags: [ long ]) }
    end
    tag = Tag.find_by!(name: long)
    at_window(1600) do
      visit_screen admin_tags_path
      details(tag)
      measured = page.evaluate_script(<<~JS)
        (() => {
          const rail = document.querySelector(".admin-tag-detail")
          const box = rail.getBoundingClientRect()
          const out = Array.from(rail.querySelectorAll("*")).filter((element) => {
            const r = element.getBoundingClientRect()
            if (r.width === 0 && r.height === 0) return false
            return r.left < box.left - 0.5 || r.right > box.right + 0.5
          }).map((element) => element.outerHTML.slice(0, 80))
          return { out, scroll: rail.scrollWidth, client: rail.clientWidth }
        })()
      JS
      assert_empty measured["out"]
      assert_operator measured["scroll"], :<=, measured["client"]
    end
  end
end
