require "application_system_test_case"

# The Settings screen in a real browser (round 3, Task 5): one form, one save
# footer. Switching the language tabs is not a change and asks nothing, a
# sidebar link or Back with a typed change asks first, a social link row added
# and removed is counted and uncounted, Save toasts "Settings saved" with both
# languages persisted, and the footer's Cancel discards without asking.
class Admin::SettingsSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    root_page
    Mobility.with_locale(:en) { site_settings(:default).update!(title: "Dana's Notes", tagline: "Things I learned") }
    sign_in_via_form(users(:one))
  end

  def footer = ".admin-save-bar"

  test "at 1600px every card is 760px wide, a text field fills it and Time zone keeps its own width" do
    page.driver.resize(1600, 1000)
    visit admin_settings_path
    await_admin_controllers

    width = ->(selector) { page.evaluate_script("document.querySelector(#{selector.to_json}).getBoundingClientRect().width") }
    %w[#settings-site-card [aria-labelledby=languages] [aria-labelledby=publishing] [aria-labelledby=ai]].each do |card|
      assert_in_delta 760, width.(card), 1, card
    end
    assert_operator width.("#settings-en-title"), :>, 700
    assert_operator width.("#settings-time_zone"), :<=, 384
  ensure
    page.driver.resize(1400, 1400)
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
    click_on "Save"
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
    click_on "Save"

    assert_selector "#toasts .admin-toast", text: "Settings saved"
    assert_equal({ "GitHub" => "https://github.com/dana", "Blog" => "https://example.org/blog" }, site_settings(:default).reload.social_links)
    assert_selector "[data-admin--settings--repeat-rows-target=list] input[name$='[name]']", count: 2
  end

  test "Back with a typed change asks first, and Cancel discards without asking" do
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

    within(footer) { click_link "Cancel" }
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

  test "the section in view is the nav's current one, in ink with the bar, and follows the scroll" do
    # Short enough that Publishing's heading can be scrolled to the top without the page's end stopping it.
    page.driver.resize(1400, 400)
    visit admin_settings_path
    await_admin_controllers
    nav = "nav[aria-label='Settings sections']"

    assert_selector "#{nav} a[aria-current=true]", text: "Site", count: 1
    look = page.evaluate_script("(() => { const s = getComputedStyle(document.querySelector(#{"#{nav} a[aria-current=true]".to_json})); return [ s.color, s.boxShadow ] })()")
    ink = page.evaluate_script("getComputedStyle(document.body).getPropertyValue('--cs-ink')")
    assert_match(/inset/, look[1])
    assert_equal look[0], page.evaluate_script("(() => { const p = document.createElement('p'); p.style.color = #{ink.strip.to_json}; document.body.append(p); const c = getComputedStyle(p).color; p.remove(); return c })()")

    page.execute_script("document.getElementById('publishing').scrollIntoView({ block: 'start' })")
    assert_selector "#{nav} a[aria-current=true]", text: "Publishing", count: 1
  ensure
    page.driver.resize(1400, 1400)
  end

  test "at the end of a page that scrolls the last section is current, though its heading is not above the 40% line" do
    # A window tall enough that the last card's (Mail's) heading is still below the 40% line at the page's end:
    # only the nav's at-end rule can make it current.
    page.driver.resize(1400, 2400)
    visit admin_settings_path
    await_admin_controllers
    page.execute_script("window.scrollTo(0, document.documentElement.scrollHeight)")

    assert page.evaluate_script("document.getElementById('mail').getBoundingClientRect().top > window.innerHeight * 0.4"), "the premise: the Mail heading is below the 40% line at the end"
    assert page.evaluate_script("document.documentElement.scrollHeight > window.innerHeight"), "the premise: the page scrolls"
    assert_selector "nav[aria-label='Settings sections'] a[aria-current=true]", text: "Mail", count: 1
  ensure
    page.driver.resize(1400, 1400)
  end

  test "below 1024px the cards are no wider than the form maximum" do
    page.driver.resize(900, 1000)
    visit admin_settings_path
    await_admin_controllers
    width = page.evaluate_script("document.getElementById('ai').closest('.flex.min-w-0.flex-col').getBoundingClientRect().width")
    max = page.evaluate_script("parseFloat(getComputedStyle(document.body).getPropertyValue('--cs-form-max'))")
    assert_operator max, :>, 0
    assert_operator width, :<=, max + 0.5
  ensure
    page.driver.resize(1400, 1400)
  end

  test "on a window where nothing scrolls the first section is current" do
    page.driver.resize(1400, 4000)
    visit admin_settings_path
    await_admin_controllers

    assert_selector "nav[aria-label='Settings sections'] a[aria-current=true]", text: "Site", count: 1
  ensure
    page.driver.resize(1400, 1400)
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
    press "Save"
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
    click_on "Save"

    assert_selector ".admin-error-summary a[href='#settings-en-title']"
    assert_selector "#settings-en-title"
    click_on "Deutsch"
    assert_no_selector "#settings-en-title"
    find(".admin-error-summary a[href='#settings-en-title']").click
    assert_selector "#settings-en-title:focus"
  end

  # ⌘K "Settings › AI translation" used ON Settings is a `_top` link to a
  # section of the screen that is showing. As a visit it asked "Leave without
  # saving?" about a jump that leaves nothing (final wave B).
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

  # Ledger C-M6: Cancel on Settings leads to Settings. A reload is no new place.
  test "the footer's Cancel reloads the screen without a second history entry" do
    visit admin_settings_path
    await_admin_controllers
    fill_in "settings-en-title", with: "Typed, then cancelled"
    entries = page.evaluate_script("history.length")
    page.execute_script("document.querySelector('#settings-form').dataset.before = 'yes'")

    within(footer) { click_link "Cancel" }
    assert_no_selector "#settings-form[data-before]"
    assert_selector footer, text: /No unsaved changes/i
    assert_equal entries, page.evaluate_script("history.length")
    assert_no_selector "#{footer} a[data-turbo-action]"
  end

  # Task 9 M14: a file dropped beside a drop zone must not navigate away.
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

  # -- Languages (round 3, Task 6) ---------------------------------------------------

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

    # D10: Default, Turn off and Add wait for Save or Cancel, and say so.
    assert_selector "#settings-languages-card button[disabled]", text: "Make default…", count: 2
    assert_selector "#settings-languages-card button[disabled]", text: "Turn off…", count: 2
    assert_selector "#settings-languages-card button[disabled]", text: "Add language"
    assert_selector "#settings-languages-card select#language-add-code[disabled]"
    assert_selector "#settings-languages-card", text: "Save or cancel your changes first."

    click_on "Save"
    assert_selector "#toasts .admin-toast", text: "Settings saved"
    assert_selector footer, text: /No unsaved changes/i
    assert_equal %w[de en es], site_settings(:default).reload.locale_codes
    assert_language_order %w[de en es]
    assert_equal "Deutsch", language_tab_names.first
    assert_selector "#settings-languages-card button:not([disabled])", text: "Make default…", count: 2
    assert_no_text "Save or cancel your changes first."
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
    click_on "Save"
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
