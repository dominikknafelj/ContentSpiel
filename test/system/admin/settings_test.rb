require "application_system_test_case"

# The Settings screen in a real browser: one form, one save
# footer. Switching the language tabs is not a change and asks nothing, a
# sidebar link or Back with a typed change asks first, a social link row added
# and removed is counted and uncounted, Save toasts "Settings saved" with both
# languages persisted, and the footer's Discard discards without asking.
class Admin::SettingsSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    root_page
    Mobility.with_locale(:en) { site_settings(:default).update!(title: "Dana's Notes", tagline: "Things I learned") }
    sign_in_via_form(users(:one))
  end

  def footer = ".admin-save-bar"

  # Docked, the cards' column narrows below 1346px of the Settings area
  # (nav, gaps and rail take 586px); at 1900px it has its full width.
  test "at 1900px every card is 760px wide, a text field fills it and Time zone keeps its own width" do
    page.current_window.resize_to(1900, 1000)
    visit_screen admin_settings_path

    width = ->(selector) { page.evaluate_script("document.querySelector(#{selector.to_json}).getBoundingClientRect().width") }
    %w[#settings-site-card [aria-labelledby=languages] [aria-labelledby=publishing] [aria-labelledby=ai]].each do |card|
      assert_in_delta 760, width.(card), 1, card
    end
    assert_operator width.("#settings-en-title"), :>, 700
    assert_operator width.("#settings-time_zone"), :<=, 384
  ensure
    page.current_window.resize_to(1400, 1400)
  end

  # -- the rail -----------------------------------------------------

  # The layout's boxes, from the DOM: the Settings area (the container),
  # the nav's wrapper, the rail, the cards' column and the first card, with
  # the rail's ground and the two grounds it may stand on (read from a probe
  # that uses each token, so all are computed values).
  def layout
    page.evaluate_script(<<~JS)
      (() => {
        const box = (element) => { const r = element.getBoundingClientRect(); return { left: r.left, right: r.right, top: r.top, bottom: r.bottom, width: r.width } }
        const token = (name) => {
          const probe = document.createElement("div")
          probe.style.backgroundColor = `var(${name})`
          document.body.append(probe)
          const value = getComputedStyle(probe).backgroundColor
          probe.remove()
          return value
        }
        const rail = document.querySelector("aside.admin-settings-glance")
        return {
          container: box(document.querySelector(".admin-settings-layout")),
          nav: box(document.querySelector(".admin-settings-layout__nav")),
          rail: box(rail),
          cards: box(document.querySelector(".admin-settings-layout__cards")),
          first_card: box(document.querySelector("#settings-site-card")),
          rail_background: getComputedStyle(rail).backgroundColor,
          rail_token: token("--cs-rail"),
          surface_token: token("--cs-surface"),
          gap: parseFloat(getComputedStyle(document.body).getPropertyValue("--cs-sp-4"))
        }
      })()
    JS
  end

  def docked?(boxes) = boxes["rail"]["left"] >= boxes["cards"]["right"] && (boxes["rail"]["top"] - boxes["cards"]["top"]).abs < 1

  test "at 1600px the rail stands right of the cards, on the rail's ground, and stays in view down the page" do
    at_window(1600, height: 700) do
      visit_screen admin_settings_path
      boxes = layout
      assert docked?(boxes), boxes.inspect
      assert_in_delta boxes["cards"]["right"] + 28, boxes["rail"]["left"], 1, "the rail stands --cs-rail-gap right of the cards"
      assert_in_delta 360, boxes["rail"]["width"], 1, "the rail is --cs-rail-width"
      assert_in_delta boxes["container"]["width"] - 586, boxes["cards"]["width"], 1, "the cards' column takes what the nav, the gaps and the rail leave"
      assert_in_delta boxes["nav"]["right"] + 28, boxes["cards"]["left"], 1, "the cards stand --cs-rail-gap right of the nav"
      assert_in_delta boxes["container"]["left"], boxes["nav"]["left"], 1, "below the content max the composition stands at the left"
      assert_equal boxes["rail_token"], boxes["rail_background"]
      assert_selector "aside.admin-settings-glance a", count: 4

      page.execute_script("window.scrollTo(0, document.documentElement.scrollHeight)")
      assert_eventually(message: "the page did not scroll") { page.evaluate_script("window.scrollY") > 300 }
      rail = layout["rail"]
      assert_in_delta boxes["gap"], rail["top"], 1, "the rail sticks --cs-sp-4 under the window's top"
      assert_operator rail["bottom"], :<=, 700 - boxes["gap"] + 1, "and ends inside the window"
    end
  end

  test "at 1100px the rail is a card above the first card, beside the nav" do
    at_window(1100) do
      visit_screen admin_settings_path
      boxes = layout
      assert_not docked?(boxes), boxes.inspect
      assert_operator boxes["rail"]["left"], :>=, boxes["nav"]["right"], "beside the nav"
      assert_in_delta boxes["first_card"]["left"], boxes["rail"]["left"], 1, "in the cards' column"
      assert_operator boxes["rail"]["bottom"], :<=, boxes["cards"]["top"], "above the first card"
      assert_in_delta boxes["first_card"]["width"], boxes["rail"]["width"], 1, "as wide as the cards"
      assert_equal boxes["surface_token"], boxes["rail_background"], "a card's ground"
    end
  end

  # Below 1280px the sidebar is a drawer and takes no width, so a 1279px
  # window gives the Settings area more room than a 1280px one. The widths
  # are asserted first: a change of the sidebar's width then fails here by
  # name rather than passing for another reason.
  test "the rail follows the Settings area's own width: a 1279px window docks it, a 1280px one does not" do
    at_window(1279) do
      visit_screen admin_settings_path
      boxes = layout
      assert_operator boxes["container"]["width"], :>=, 1200
      assert docked?(boxes), boxes.inspect
    end
    at_window(1280) do
      visit_screen admin_settings_path
      boxes = layout
      assert_operator boxes["container"]["width"], :<, 1200
      assert_not docked?(boxes), boxes.inspect
    end
  end

  # The rail comes after the nav and before the cards in the document, so
  # the Tab order is the nav's links, the rail's rows, then the first card;
  # a row is one stop, its state chips none.
  test "the rail's states are words a keyboard passes over: each row is one link, and no chip takes the focus" do
    at_window(1600) do
      visit_screen admin_settings_path
      # A press on the heading puts the sequential focus starting point there.
      find(".admin-settings-layout h1").click
      stops = Array.new(12) do
        page.send_keys(:tab)
        page.evaluate_script(<<~JS)
          (() => {
            const element = document.activeElement
            if (element.closest(".admin-state-chip")) return "chip"
            if (element.closest("nav[aria-label='Settings sections']")) return element.getAttribute("href")
            if (element.closest("aside.admin-settings-glance")) return element.id
            if (element.closest("#settings-site-card")) return "site card"
            return element.outerHTML
          })()
        JS
      end
      assert_equal [ *%w[#site #languages #publishing #forms #ai #mail #images],
                     *%w[settings-glance-languages settings-glance-ai settings-glance-mail settings-glance-images], "site card" ], stops
    end
  end

  # A row is a same-page link, as the nav's are: nothing is left, so the
  # leave guard does not ask, and the typed change stays counted.
  test "a rail link with typed changes jumps to its card without asking" do
    visit_screen admin_settings_path
    fill_in "settings-en-title", with: "Typed, then glanced"
    assert_selector footer, text: /\b1 unsaved change\b/i
    entries = page.evaluate_script("history.length")

    find("a#settings-glance-mail").click

    assert_selector "#mail:focus"
    assert_no_selector "dialog#leave-dialog[open]"
    assert_equal entries, page.evaluate_script("history.length")
    assert_equal "Typed, then glanced", find_field("settings-en-title").value
    assert_selector footer, text: /\b1 unsaved change\b/i
  end

  # A mail field saved through the bar is a change of the delivery
  # settings, so a working site is untested again, and the rail says so.
  test "saving a mail field puts the rail's Mail row back to Saved, not tested" do
    with_mail_state(:working) do
      visit_screen admin_settings_path
      assert_selector "#settings-glance-mail .admin-state-chip[data-state-tone=ok]", text: "Working"

      fill_in "settings-mail_server", with: "smtp.other.test"
      click_on "Save changes"

      assert_selector "#toasts .admin-toast", text: "Settings saved"
      assert_selector "#settings-glance-mail .admin-state-chip[data-state-tone=warn]", text: "Saved, not tested"
    end
  end

  test "tabs switch without asking or counting, a sidebar link asks, and Save persists both languages" do
    visit admin_settings_path
    await_admin_controllers
    assert_selector footer, text: /No unsaved changes/i

    click_on "Deutsch"
    assert_selector "button[role=tab][aria-selected=true]", text: "Deutsch"
    assert_selector "#settings-de-title", visible: :visible
    assert_no_selector "#settings-en-title"
    assert_no_selector "dialog#leave-dialog[open]"
    fill_in "settings-de-title", with: "Danas Notizen"
    assert_selector footer, text: /1 unsaved change/i

    click_on "English"
    assert_selector "#settings-en-title"
    assert_no_selector "dialog#leave-dialog[open]"
    assert_selector footer, text: /1 unsaved change/i
    click_on "Deutsch"
    assert_equal "Danas Notizen", find_field("settings-de-title").value

    within("nav[aria-label='Modules']") { click_link "Posts" }
    assert_selector "dialog#leave-dialog[open]"
    within("dialog#leave-dialog") do
      assert_text "You have 1 unsaved change on this screen."
      press "Keep editing"
    end
    assert_current_path admin_settings_path
    assert_equal "Danas Notizen", find_field("settings-de-title").value

    # A social link row added is counted, and removed it is not.
    click_on "+ Add link"
    assert_selector "[data-admin--settings--repeat-rows-target=list] input[name$='[name]']", count: 1
    assert_selector footer, text: /\b1 unsaved change\b/i # a blank row is nothing yet
    page.all("[data-admin--settings--repeat-rows-target=row]").last.find("input[name$='[name]']").set("GitHub")
    assert_selector footer, text: /\b2 unsaved changes\b/i # typed in, it is one more
    page.all("[data-admin--settings--repeat-rows-target=row]").last.find("button[aria-label='Remove link']").click
    assert_selector footer, text: /\b1 unsaved change\b/i # and gone with its row
    assert_no_selector "[data-admin--settings--repeat-rows-target=list] input"

    click_on "English"
    fill_in "settings-en-tagline", with: "Things I learned lately"
    click_on "Save changes"
    assert_selector "#toasts .admin-toast", text: "Settings saved"
    assert_selector footer, text: /No unsaved changes/i
    site = site_settings(:default).reload
    assert_equal "Danas Notizen", site.title(locale: "de")
    assert_equal "Things I learned lately", site.tagline(locale: "en")
    assert_equal "Dana's Notes", site.title(locale: "en")
  end

  test "an added social link is saved with the rest" do
    visit admin_settings_path
    await_admin_controllers

    click_on "+ Add link"
    fill_in "settings-social-0-name", with: "GitHub"
    fill_in "settings-social-0-url", with: "https://github.com/dana"
    click_on "+ Add link"
    fields = page.all("[data-admin--settings--repeat-rows-target=row]").last
    fields.find("input[name$='[name]']").set("Blog")
    fields.find("input[name$='[url]']").set("https://example.org/blog")
    click_on "Save changes"

    assert_selector "#toasts .admin-toast", text: "Settings saved"
    assert_equal({ "GitHub" => "https://github.com/dana", "Blog" => "https://example.org/blog" }, site_settings(:default).reload.social_links)
    assert_selector "[data-admin--settings--repeat-rows-target=list] input[name$='[name]']", count: 2
  end

  # Review Focus 1. A refused save brings back what was typed, which is then
  # the browser's own baseline: the server says which fields differ from the
  # saved settings. A field both changed and invalid shows its invalid edge
  # alone (Port), and is named all the same.
  test "after a refused save the typed fields that differ from the saved settings carry the mark and the bar names them" do
    site_settings(:default).update!(mail_server: "smtp.saved.test", mail_port: 587)
    visit_screen admin_settings_path
    fill_in "settings-mail_server", with: "smtp.typed.test"
    # The browser would stop the number at its own limit; the server's rule
    # is the one under test.
    page.execute_script("document.getElementById('settings-mail_port').removeAttribute('max')")
    fill_in "settings-mail_port", with: "70000"
    click_on "Save changes"

    assert_selector "#settings-mail_port-errors p"
    assert_selector "[data-field-name=mail_server][data-save-bar-changed=saved]"
    assert_selector "[data-field-name=mail_port][data-save-bar-changed=saved]"
    edge = ->(id) { page.evaluate_script("(() => { const s = getComputedStyle(document.getElementById('#{id}')); return [ s.boxShadow, s.borderBottomColor ] })()") }
    danger = page.evaluate_script("(() => { const p = document.createElement('i'); p.style.color = 'var(--cs-danger)'; document.body.append(p); const c = getComputedStyle(p).color; p.remove(); return c })()")
    assert_match(/inset/, edge.("settings-mail_server")[0])
    port = edge.("settings-mail_port")
    assert_equal "none", port[0]
    assert_equal danger, port[1]
    assert_selector footer, text: "2 unsaved changes · Server, Port"

    within("nav[aria-label='Modules']") { click_link "Posts" }
    assert_selector "dialog#leave-dialog[open]"
    within("dialog#leave-dialog") { press "Keep editing" }
    assert_current_path admin_settings_path
  end

  test "Back with a typed change asks first, and Discard discards without asking" do
    visit admin_root_path
    await_admin_controllers
    within("nav[aria-label='Modules']") { click_link "Settings" }
    assert_current_path admin_settings_path
    assert_selector footer, text: /No unsaved changes/i

    fill_in "settings-en-title", with: "Typed before Back"
    page.execute_script("history.back()")
    assert_selector "dialog#leave-dialog[open]"
    within("dialog#leave-dialog") { press "Keep editing" }
    assert_current_path admin_settings_path
    assert_equal "Typed before Back", find_field("settings-en-title").value

    within(footer) { click_link "Discard" }
    assert_no_selector "dialog#leave-dialog[open]"
    assert_field "settings-en-title", with: "Dana's Notes"
    assert_selector footer, text: /No unsaved changes/i
  end

  test "the nav's anchors jump within the page without asking or adding history" do
    visit admin_settings_path
    await_admin_controllers
    fill_in "settings-en-title", with: "Typed, then jump"
    entries = page.evaluate_script("history.length")

    within("nav[aria-label='Settings sections']") { click_link "AI translation" }

    # The focus arriving is what says the jump has happened; everything else is read after it.
    assert_selector "#ai:focus"
    assert_no_selector "dialog#leave-dialog[open]"
    assert_equal entries, page.evaluate_script("history.length")
    assert_equal "Typed, then jump", find_field("settings-en-title").value
  end

  test "the section in view is the nav's current one, on the accent tint, and follows the scroll" do
    # Short enough that Publishing's heading can be scrolled to the top without the page's end stopping it.
    page.current_window.resize_to(1400, 400)
    visit_screen admin_settings_path
    nav = "nav[aria-label='Settings sections']"

    assert_selector "#{nav} a[aria-current=true]", text: "Site", count: 1
    look = page.evaluate_script("(() => { const s = getComputedStyle(document.querySelector(#{"#{nav} a[aria-current=true]".to_json})); return [ s.color, s.backgroundColor, s.fontWeight, s.boxShadow ] })()")
    resolved = ->(token, property) { page.evaluate_script("(() => { const p = document.createElement('p'); p.style.#{property} = getComputedStyle(document.body).getPropertyValue(#{token.to_json}).trim(); document.body.append(p); const c = getComputedStyle(p).#{property}; p.remove(); return c })()") }
    assert_equal resolved.("--cs-ink", "color"), look[0]
    assert_equal resolved.("--cs-accent-tint", "backgroundColor"), look[1]
    assert_equal "600", look[2]
    assert_equal "none", look[3], "no bar: the tint alone marks the current link"
    other = page.evaluate_script("getComputedStyle(document.querySelector(#{"#{nav} a:not([aria-current])".to_json})).backgroundColor")
    assert_not_equal look[1], other

    page.execute_script("document.getElementById('publishing').scrollIntoView({ block: 'start' })")
    assert_selector "#{nav} a[aria-current=true]", text: "Publishing", count: 1
  ensure
    page.current_window.resize_to(1400, 1400)
  end

  test "at the end of a page that scrolls the last section is current, though its heading is not above the 40% line" do
    # A window tall enough that the last card's (Images') heading is still below the 40% line at the page's end:
    # only the nav's at-end rule can make it current.
    page.current_window.resize_to(1400, 2400)
    visit admin_settings_path
    await_admin_controllers
    page.execute_script("window.scrollTo(0, document.documentElement.scrollHeight)")

    assert page.evaluate_script("document.getElementById('images').getBoundingClientRect().top > window.innerHeight * 0.4"), "the premise: the Images heading is below the 40% line at the end"
    assert page.evaluate_script("document.documentElement.scrollHeight > window.innerHeight"), "the premise: the page scrolls"
    assert_selector "nav[aria-label='Settings sections'] a[aria-current=true]", text: "Images", count: 1
  ensure
    page.current_window.resize_to(1400, 1400)
  end

  test "below 1024px the cards are no wider than the form maximum" do
    page.current_window.resize_to(900, 1000)
    visit admin_settings_path
    await_admin_controllers
    width = page.evaluate_script("document.querySelector('.admin-settings-layout__cards').getBoundingClientRect().width")
    max = page.evaluate_script("parseFloat(getComputedStyle(document.body).getPropertyValue('--cs-form-max'))")
    assert_operator max, :>, 0
    assert_operator width, :<=, max + 0.5
  ensure
    page.current_window.resize_to(1400, 1400)
  end

  test "on a window where nothing scrolls the first section is current" do
    page.current_window.resize_to(1400, 4000)
    visit admin_settings_path
    await_admin_controllers

    assert_selector "nav[aria-label='Settings sections'] a[aria-current=true]", text: "Site", count: 1
  ensure
    page.current_window.resize_to(1400, 1400)
  end

  test "a blank social row counts nothing, a typed label counts one" do
    visit admin_settings_path
    await_admin_controllers

    click_on "+ Add link"
    assert_selector footer, text: /No unsaved changes/i
    page.all("[data-admin--settings--repeat-rows-target=row]").last.find("input[name$='[name]']").set("GitHub")
    assert_selector footer, text: /\b1 unsaved change/i
  end

  test "removing the only social link removes its row, and Save deletes it" do
    site_settings(:default).update!(social_links: { "GitHub" => "https://github.com/dana" })
    visit admin_settings_path
    await_admin_controllers

    find("button[aria-label='Remove link']").click
    assert_selector footer, text: /unsaved change/i
    assert_no_selector "[data-admin--settings--repeat-rows-target=row]"
    assert_selector "button[data-action='admin--settings--repeat-rows#add']:focus"
    press "Save changes"
    assert_selector "#toasts .admin-toast", text: "Settings saved"
    assert_equal({}, site_settings(:default).reload.social_links.to_h)
    visit admin_settings_path
    assert_no_field "settings-social-0-name"
  end

  test "the error summary's link reveals the hidden panel and focuses the field" do
    visit "#{admin_settings_path}?locale=de"
    await_admin_controllers
    fill_in "settings-de-title", with: "Danas Notizen"
    click_on "English"
    fill_in "settings-en-title", with: ""
    click_on "Deutsch"
    click_on "Save changes"

    assert_selector ".admin-error-summary a[href='#settings-en-title']"
    assert_selector "#settings-en-title"
    click_on "Deutsch"
    assert_no_selector "#settings-en-title"
    find(".admin-error-summary a[href='#settings-en-title']").click
    assert_selector "#settings-en-title:focus"
  end

  # ⌘K "Settings › AI translation" used ON Settings is a `_top` link to a
  # section of the screen that is showing. It is no visit: a visit would ask
  # "Leave without saving?" about a jump that leaves nothing.
  test "a ⌘K row for a section of this screen jumps there without asking, changes kept" do
    visit admin_settings_path
    await_admin_controllers
    fill_in "settings-en-title", with: "Typed, not saved"
    assert_selector footer, text: /\b1 unsaved change\b/i
    entries = page.evaluate_script("history.length")

    find("body").send_keys([ :control, "k" ])
    input = find("dialog#command-palette input")
    input.set("AI translation")
    assert_selector "#jump-results [role=option][aria-selected=true]", text: "Settings › AI translation"
    input.send_keys(:enter)

    assert_no_selector "dialog[open]"
    assert_eventually(message: "focus never reached the section") { page.evaluate_script("document.activeElement.id") == "ai" }
    assert_equal "Typed, not saved", find_field("settings-en-title").value
    assert_selector footer, text: /\b1 unsaved change\b/i
    assert_equal entries, page.evaluate_script("history.length")
    assert_equal "", page.evaluate_script("location.hash")
  end

  # Discard on Settings leads to Settings. A reload is no new place.
  test "the footer's Discard reloads the screen without a second history entry" do
    visit admin_settings_path
    await_admin_controllers
    fill_in "settings-en-title", with: "Typed, then cancelled"
    entries = page.evaluate_script("history.length")
    page.execute_script("document.querySelector('#settings-form').dataset.before = 'yes'")

    within(footer) { click_link "Discard" }
    assert_no_selector "#settings-form[data-before]"
    assert_selector footer, text: /No unsaved changes/i
    assert_equal entries, page.evaluate_script("history.length")
    assert_no_selector "#{footer} a[data-turbo-action]"
  end

  # A file dropped beside a drop zone must not navigate away.
  test "a file dropped on a screen that takes none is refused, not navigated to" do
    visit admin_settings_path
    await_admin_controllers

    prevented = page.evaluate_script(<<~JS)
      (() => {
        const data = new DataTransfer()
        data.items.add(new File(["x"], "stray.png", { type: "image/png" }))
        const over = new DragEvent("dragover", { dataTransfer: data, bubbles: true, cancelable: true })
        const drop = new DragEvent("drop", { dataTransfer: data, bubbles: true, cancelable: true })
        const heading = document.querySelector("h1")
        heading.dispatchEvent(over)
        heading.dispatchEvent(drop)
        const text = new DataTransfer()
        text.setData("text/plain", "words")
        const words = new DragEvent("drop", { dataTransfer: text, bubbles: true, cancelable: true })
        heading.dispatchEvent(words)
        return [over.defaultPrevented, drop.defaultPrevented, words.defaultPrevented]
      })()
    JS
    assert_equal [ true, true, false ], prevented
  end

  # -- Languages ---------------------------------------------------

  def language_tab_names = page.all("#settings-site-card nav.admin-language-tabs [role=tab]").map(&:text)

  # The rows' order, waited for: a drop, an Escape and a re-render each move the
  # rows a moment after the key or the answer, so one read can see the old order.
  def assert_language_order(codes)
    seen = nil
    assert_eventually(message: -> { "the language rows never read #{codes.inspect} (last seen #{seen.inspect})" }) do
      seen = page.all("#settings-languages-card li[data-code]").map { |li| li["data-code"] }
      seen == codes
    end
  end

  test "a keyboard reorder is one pending change, locks the instant actions, and Save puts the tabs in the new order" do
    visit admin_settings_path
    await_admin_controllers
    assert_selector "#settings-languages-card button:not([disabled])", text: "Make default…", count: 2

    handle = find("button[aria-label='Move English']")
    handle.send_keys(:space)
    assert_selector "[data-admin--settings--sortable-rows-target=announcer]", text: /Picked up English\. Position 1 of 3/, visible: :all
    handle.send_keys(:down)
    handle.send_keys(:space)
    assert_selector "[data-admin--settings--sortable-rows-target=announcer]", text: /Dropped English\. Position 2 of 3/, visible: :all
    assert_language_order %w[de en es]
    assert_selector footer, text: /\b1 unsaved change\b/i

    # Default, Turn off and Add wait for Save or Discard, and say so.
    assert_selector "#settings-languages-card button[disabled]", text: "Make default…", count: 2
    assert_selector "#settings-languages-card button[disabled]", text: "Turn off…", count: 2
    assert_selector "#settings-languages-card button[disabled]", text: "Add language"
    assert_selector "#settings-languages-card select#language-add-code[disabled]"
    assert_selector "#settings-languages-card", text: "Save or discard your changes first."

    click_on "Save changes"
    assert_selector "#toasts .admin-toast", text: "Settings saved"
    assert_selector footer, text: /No unsaved changes/i
    assert_equal %w[de en es], site_settings(:default).reload.locale_codes
    assert_language_order %w[de en es]
    assert_equal "Deutsch", language_tab_names.first
    assert_selector "#settings-languages-card button:not([disabled])", text: "Make default…", count: 2
    assert_no_text "Save or discard your changes first."
  end

  test "Escape puts a picked row back and counts nothing" do
    visit admin_settings_path
    await_admin_controllers

    handle = find("button[aria-label='Move English']")
    handle.send_keys(:space)
    handle.send_keys(:down)
    handle.send_keys(:escape)

    assert_language_order %w[en de es]
    assert_selector footer, text: /No unsaved changes/i
  end

  test "choosing a fallback is one pending change; Save stores it" do
    visit admin_settings_path
    await_admin_controllers

    select "English", from: "language-de-fallback"
    assert_selector footer, text: /\b1 unsaved change\b/i
    click_on "Save changes"
    assert_selector "#toasts .admin-toast", text: "Settings saved"
    assert_equal [ "en" ], site_settings(:default).reload.locale_entry("de")["fallbacks"]
  end

  test "Make default opens the dialog with its count, Cancel changes nothing, and confirming changes the default" do
    Mobility.with_locale(:de) { site_settings(:default).update!(title: "Danas Notizen") }
    visit admin_settings_path
    await_admin_controllers
    assert_selector "#language-en [data-default-tag]", text: /default/i
    assert_no_selector "#settings-languages-card input[type=radio]"

    find("button[aria-label='Make Deutsch the default language']").click
    assert_selector "dialog#language-default-dialog-de[open]"
    within("dialog#language-default-dialog-de") do
      assert_text "Make Deutsch the default?"
      assert_text(/Deutsch becomes the source language, so every translation is marked outdated \(\d+ items?\)\./)
      click_on "Cancel"
    end
    assert_no_selector "dialog[open]"
    assert_selector "#language-en [data-default-tag]"
    assert_no_selector "#language-de [data-default-tag]"
    assert_selector footer, text: /No unsaved changes/i

    # A button opens its dialog when pressed, never on arriving: focus alone
    # asks nothing (the radios opened a dialog per arrow key).
    page.execute_script("document.querySelector(\"button[aria-label='Make Deutsch the default language']\").focus()")
    assert_no_selector "dialog[open]"

    find("button[aria-label='Make Deutsch the default language']").click
    within("dialog#language-default-dialog-de") { click_on "Change default language" }

    assert_selector "#toasts .admin-toast", text: "Deutsch is now the default language"
    # Back on Settings itself (the 303 names `#languages`; the path and query are what a browser reports).
    assert_current_path admin_settings_path
    assert_selector "#language-de [data-default-tag]", text: /default/i
    assert_selector "button[aria-label='Make English the default language']"
    site = site_settings(:default).reload
    assert_equal "de", site.default_locale.to_s
    assert_equal "Danas Notizen", site.title(locale: "de")
    assert_equal "Dana's Notes", site.title(locale: "en")
  end

  test "Turn off asks first and turns the language off; Add language adds it" do
    visit admin_settings_path
    await_admin_controllers

    find("button[aria-label='Turn off Español']").click
    within("dialog#language-off-dialog-es") do
      assert_text "Turn off Español?"
      click_on "Turn off Español"
    end
    assert_selector "#toasts .admin-toast", text: "Español turned off"
    assert_no_selector "#language-es"
    assert_equal %w[en de], site_settings(:default).reload.locale_codes

    select "Français (FR)", from: "language-add-code"
    click_on "Add language"
    assert_selector "#toasts .admin-toast", text: "Français added"
    assert_selector "#language-fr"
  end

  # SortableJS's fallback drag appends a clone of the row to <body>; it must
  # stay a picture (no ids, no names, no Stimulus wiring) and the drop is one
  # pending change.
  test "dragging the default language's row with the mouse reorders it and keeps its Default tag" do
    visit admin_settings_path
    await_admin_controllers
    assert_selector "#language-en [data-default-tag]"

    # A real pointer drag in small steps: SortableJS's fallback needs
    # `fallbackTolerance` of movement and then moves over the target row.
    mouse = page.driver.browser.mouse
    from = find("button[aria-label='Move English']").evaluate_script("(function(r){return [r.x + r.width / 2, r.y + r.height / 2]})(this.getBoundingClientRect())")
    target = find("#language-de").evaluate_script("(function(r){return [r.x + r.width / 2, r.y + r.height * 0.8]})(this.getBoundingClientRect())")
    mouse.move(x: from[0], y: from[1])
    mouse.down
    10.times { |step| mouse.move(x: from[0] + (target[0] - from[0]) * (step + 1) / 10.0, y: from[1] + (target[1] - from[1]) * (step + 1) / 10.0, steps: 3) }
    assert_selector "body > .admin-drag-fallback", visible: :all
    assert_no_selector "body > .admin-drag-fallback [id], body > .admin-drag-fallback [name]", visible: :all
    mouse.up

    assert_language_order %w[de en es]
    assert_selector footer, text: /\b1 unsaved change\b/i
    assert_selector "#language-en [data-default-tag]", count: 1
  end

  test "a pointer drag ends a keyboard pick-up" do
    visit admin_settings_path
    await_admin_controllers

    handle = find("button[aria-label='Move English']")
    handle.send_keys(:space)
    assert_selector "#language-en[data-picked]"

    mouse = page.driver.browser.mouse
    from = handle.evaluate_script("(function(r){return [r.x + r.width / 2, r.y + r.height / 2]})(this.getBoundingClientRect())")
    target = find("#language-de").evaluate_script("(function(r){return [r.x + r.width / 2, r.y + r.height * 0.8]})(this.getBoundingClientRect())")
    mouse.move(x: from[0], y: from[1])
    mouse.down
    10.times { |step| mouse.move(x: from[0] + (target[0] - from[0]) * (step + 1) / 10.0, y: from[1] + (target[1] - from[1]) * (step + 1) / 10.0, steps: 3) }
    assert_selector "body > .admin-drag-fallback", visible: :all
    assert_no_selector "#settings-languages-card li[data-picked]"
    mouse.up

    assert_language_order %w[de en es]
    assert_selector footer, text: /\b1 unsaved change\b/i
  end

  # The default's row has no Turn off button; an unseen copy holds its place,
  # so the tag and the fallback select start where the other rows' do.
  test "the language rows line up: the default's tag and select start where the other rows' button and select do" do
    visit admin_settings_path(anchor: "languages")
    await_admin_controllers

    lefts = page.evaluate_script("Array.from(document.querySelectorAll('#settings-languages-card select[id$=-fallback]')).map((select) => select.getBoundingClientRect().left)")
    assert_operator lefts.size, :>=, 2
    assert_operator lefts.max - lefts.min, :<, 1, "the fallback selects start at #{lefts.inspect}"

    tag = page.evaluate_script("document.querySelector('#settings-languages-card [data-default-tag]').getBoundingClientRect().left")
    button = page.evaluate_script("Array.from(document.querySelectorAll('#settings-languages-card button')).find((b) => b.textContent.trim() === 'Make default…').getBoundingClientRect().left")
    assert_in_delta button, tag, 1
  end
end
