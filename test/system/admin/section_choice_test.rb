require "application_system_test_case"

# Choosing a section (`admin--editor--section-choice`): where the page
# editor's rail docks, a section head's words show that section's settings
# region in the rail's Section tab and outline the section; the region is the
# one element its form lives in, moved, never cloned, and put back under its
# head when it closes, when the rail undocks, before Turbo's snapshot and
# when the controller goes. Docked (1900px) unless a test says otherwise.
class Admin::SectionChoiceSystemTest < Admin::SectionsSystemTestCase
  WIDE = 1900
  NARROW = 1400

  setup do
    @second = @page.content_blocks.create!(block_type: "section", position: 1, settings: { "layout" => "two" })
    @dana = users(:two).tap { |user| user.update!(name: "Dana Weiss") }
  end

  teardown do
    page.execute_script("try { window.localStorage.removeItem('cs-notes-open') } catch (error) {}")
  end

  def card_of(section) = "##{ActionView::RecordIdentifier.dom_id(section)}"
  def in_rail(section = @section) = "#editor-grid-panel-section #{settings_region(section)}"
  def at_home(section = @section) = "#{card_of(section)} > #{settings_region(section)}"
  def close_button(section = @section) = "#{settings_region(section)} button[data-action='admin--editor--section-settings#close']"

  def docked? = page.evaluate_script("document.getElementById('editor-grid').hasAttribute('data-rail-docked')")

  def assert_docked(docked = true)
    assert_eventually(message: "the rail is #{docked ? "not " : ""}docked") { docked? == docked }
  end

  def open_docked
    open_editor
    assert_docked
  end

  # The anchor has no word of its own until one is set: the width's word
  # opens the settings, and the anchor field is pressed.
  def open_anchor(section = @section)
    find(word("width", section)).click
    find("#block-#{section.id}-anchor").click
  end

  def assert_one_region(section = @section)
    assert_equal 1, page.evaluate_script("document.querySelectorAll(#{settings_region(section).to_json}).length"), "one settings region for the section"
  end

  def assert_empty_line
    assert_selector "#editor-grid-panel-section [data-admin--editor--section-choice-target=empty]", text: "Choose a section", visible: :all
    assert_no_selector "#editor-grid-panel-section [data-admin--editor--section-choice-target=empty][hidden]", visible: :all
  end

  test "pressing a section's words shows its settings in the Section tab and outlines the section" do
    at_window(WIDE) do
      open_docked
      find(word("width")).click

      assert_selector in_rail, visible: :visible
      assert_one_region
      assert_selector "#{card_of(@section)}[data-chosen]"
      assert_selector "#editor-grid-tab-section[aria-selected=true]"
      assert_selector "#editor-grid-panel-section [data-admin--editor--section-choice-target=empty]", visible: :hidden
      assert_eventually(message: "the focus is not on the Width select") { focus_is_on("#block-#{@section.id}-width") }
      page.all("#section-#{@section.id}-words button").each do |each|
        assert_equal "true", each["aria-expanded"]
        assert_equal "section-#{@section.id}-settings", each["aria-controls"]
      end
      # The selection's outline is the accent, outside the frame.
      outline = page.evaluate_script("(() => { const style = getComputedStyle(document.querySelector(#{card_of(@section).to_json})); return [ style.outlineStyle, style.outlineWidth, style.outlineOffset ] })()")
      assert_equal [ "solid", "2px", "2px" ], outline
    end
  end

  test "nothing else of the section selects it: its ground, a tile, a handle, a lane and + Add" do
    at_window(WIDE) do
      open_docked

      body = find("#{card_of(@section)} [data-block-body]")
      body.click(x: 4, y: 4)
      await_frames
      assert_no_selector "[data-chosen]"

      find(face(@left)).click
      assert_selector panel(@left), visible: :visible
      assert_selector "#{card_of(@section)} #{panel(@left)}"
      assert_no_selector "[data-chosen]"

      find("#{card_of(@section)} > .admin-section-card__head .admin-block-card__handle").click
      await_frames
      assert_no_selector "[data-chosen]"

      find(lane(2)).click(x: 4, y: 4)
      await_frames
      assert_no_selector "[data-chosen]"

      find("#block-picker-#{@section.id}-2 button[aria-haspopup=menu]").click
      assert_selector "#block-picker-#{@section.id}-2 [role=menu]"
      keyboard.type(:escape)
      await_frames
      assert_no_selector "[data-chosen]"
      assert_selector at_home, visible: :hidden
      assert_empty_line
    end
  end

  test "with no section chosen the Section tab says Choose a section" do
    at_window(WIDE) do
      open_docked
      find("#editor-grid-tab-section").click

      assert_selector "#editor-grid-panel-section", visible: :visible, text: "Choose a section"
      assert_selector "#editor-grid-panel-section", text: "Press a section's settings, such as “3 columns ▾”, to change them here."
      assert_no_selector "#editor-grid-panel-section #{settings_region}", visible: :all
    end
  end

  test "a second section's words move the first one's settings home and show the second's" do
    at_window(WIDE) do
      open_docked
      find(word("width")).click
      assert_selector in_rail, visible: :visible

      find(word("background", @second)).click

      assert_selector in_rail(@second), visible: :visible
      assert_selector at_home, visible: :hidden
      assert_one_region
      assert_one_region(@second)
      assert_selector "[data-chosen]", count: 1
      assert_selector "#{card_of(@second)}[data-chosen]"
      assert_selector "#{word("width")}[aria-expanded='false']"
      assert_eventually(message: "the focus is not on the second section's Background") { focus_is_on("#block-#{@second.id}-background") }
    end
  end

  test "Escape and Close in the Section panel put the settings home and give the focus back to the word" do
    at_window(WIDE) do
      open_docked
      find(word("width")).click
      assert_eventually(message: "the focus is not on the Width select") { focus_is_on("#block-#{@section.id}-width") }

      keyboard.type(:escape)

      assert_selector at_home, visible: :hidden
      assert_no_selector "[data-chosen]"
      assert_selector "#{word("width")}[aria-expanded='false']"
      assert_eventually(message: "Escape did not give the focus to the word") { focus_is_on(word("width")) }
      assert_selector "#editor-grid-tab-page[aria-selected=true]"
      assert_empty_line

      find(word("background")).click
      assert_selector in_rail, visible: :visible
      find(close_button).click

      assert_selector at_home, visible: :hidden
      assert_no_selector "[data-chosen]"
      assert_eventually(message: "Close did not give the focus to the word") { focus_is_on(word("background")) }
      assert_one_region
    end
  end

  test "typing in the rail and choosing another section at once saves on the right base" do
    at_window(WIDE) do
      open_docked
      open_anchor
      find("#block-#{@section.id}-anchor").send_keys("intro")
      # Inside the anchor's debounce: the region goes home with its edit unsent.
      open_anchor(@second)
      assert_selector in_rail(@second), visible: :visible
      find("#block-#{@second.id}-anchor").send_keys("pricing")

      assert_selector "#block-#{@section.id}-save-status", text: "SAVED", visible: :all
      assert_selector "#block-#{@second.id}-save-status", text: "SAVED", visible: :all
      assert_writes_settled
      assert_equal "intro", @section.reload.settings["anchor"]
      assert_equal "pricing", @second.reload.settings["anchor"]
      assert_no_text "Changed elsewhere"
    end
  end

  test "a window narrowed while a section field in the rail has the focus puts the region under its head with the focus and the text, and the save lands on its base" do
    at_window(WIDE) do
      open_docked
      open_anchor
      field = "#block-#{@section.id}-anchor"
      assert_eventually(message: "the focus is not on the anchor") { focus_is_on(field) }
      find(field).send_keys("intro")

      page.current_window.resize_to(NARROW, 900)

      assert_docked(false)
      assert_selector at_home, visible: :visible
      assert_one_region
      assert_no_selector "[data-chosen]"
      assert_equal "intro", find(field).value
      assert_eventually(message: -> { "the focus is on #{page.evaluate_script("document.activeElement.outerHTML.slice(0, 120)")}" }) { focus_is_on(field) }
      assert_equal [ 5, 5 ], page.evaluate_script("(() => { const field = document.activeElement; return [ field.selectionStart, field.selectionEnd ] })()")
      assert_selector "#{word("width")}[aria-expanded='true']"

      assert_selector "#block-#{@section.id}-save-status", text: "SAVED"
      assert_writes_settled
      assert_equal "intro", @section.reload.settings["anchor"]
      assert_no_text "Changed elsewhere"
    end
  end

  test "below the threshold the words open the settings in place, as before" do
    at_window(NARROW) do
      open_editor
      assert_docked(false)
      find(word("width")).click

      assert_selector at_home, visible: :visible
      assert_no_selector "[data-chosen]"
      assert_no_selector "#editor-grid-panel-section #{settings_region}", visible: :all
      assert_eventually(message: "the focus is not on the Width select") { focus_is_on("#block-#{@section.id}-width") }
    end
  end

  test "removing the chosen section takes its settings out of the rail and says Choose a section" do
    at_window(WIDE) do
      open_docked
      find(word("width")).click
      assert_selector in_rail, visible: :visible

      find("#{card_of(@section)} button[aria-label='Section actions']").click
      click_button "Remove section, keep blocks"

      assert_no_selector card_of(@section)
      assert_no_selector settings_region, visible: :all
      assert_no_selector "[data-chosen]"
      assert_empty_line
      # The kept blocks are cards of the list now.
      assert_selector "#content-blocks-list > [data-block-id='#{@left.id}']"
    end
  end

  test "a colleague's removal of the chosen section, through a live list merge, takes its settings out of the rail" do
    at_window(WIDE) do
      open_docked
      await_notes_live
      find(word("width")).click
      assert_selector in_rail, visible: :visible

      as(@dana, channel: :admin) { ContentBlocks::Destroy.call(@section.reload) }

      assert_no_selector card_of(@section), wait: 8
      assert_no_selector settings_region, visible: :all
      assert_no_selector "[data-chosen]"
      assert_empty_line
    end
  end

  test "a colleague's save of the chosen section redraws its settings in the rail" do
    at_window(WIDE) do
      open_docked
      await_notes_live
      find(word("width")).click
      assert_selector in_rail, visible: :visible

      as(@dana, channel: :admin) do
        result = ContentBlocks::Save.call(@section.reload, attributes: { settings: @section.settings.merge("background" => "strong") })
        assert result.ok?, result.errors.to_sentence
      end

      assert_selector word("background"), text: "Strong background", wait: 8
      assert_eventually(message: "the rail's region never took the colleague's background") { find("#block-#{@section.id}-background", visible: :all).value == "strong" }
      assert_selector in_rail, visible: :visible
      assert_selector "#{settings_region}[data-editing-away]"
      assert_one_region
      assert_selector "#{card_of(@section)}[data-chosen]"
      assert_selector "#editor-grid-tab-section[aria-selected=true]"
      page.all("#section-#{@section.id}-words button").each do |each|
        assert_equal "true", each["aria-expanded"]
        assert_equal "section-#{@section.id}-settings", each["aria-controls"]
      end
      assert_equal "editor-grid-tab-section", find("#editor-grid-panel-section")["aria-labelledby"]
    end
  end

  test "a held section's settings shown in the rail are read-only with their hold strip" do
    Editing::Reservation.claim(subject: @section, record: @page, user: @dana, tab: "tab-bbbbbbbb", now: Time.current)
    at_window(WIDE) do
      open_docked
      assert_selector "#block-#{@section.id}-hold [data-editing-kind=held]", text: "Dana Weiss"

      find(word("width")).click

      assert_selector in_rail, visible: :visible
      assert_selector "#{in_rail} #section-#{@section.id}-form[data-editing-held=true] fieldset.admin-held", visible: :all
      assert_selector "#{in_rail} [data-held-guard]", visible: :all
      assert_selector "#block-#{@section.id}-hold [data-editing-kind=held]", text: "Dana Weiss", visible: :visible
      find("#block-#{@section.id}-anchor").send_keys("ZZZ")
      await_frames
      assert_equal "", find("#block-#{@section.id}-anchor").value
      assert_writes_settled
      assert_nil @section.reload.settings["anchor"].presence
    end
  end

  test "leaving the editor with settings in the rail sends their unsaved text first" do
    other = create_page(title: "Elsewhere")
    at_window(WIDE) do
      open_docked
      open_anchor
      find("#block-#{@section.id}-anchor").send_keys("intro")
      assert asks_before_unload?, "an edit in the rail inside its debounce was not guarded"

      find("#tree a", text: "Elsewhere").click
      assert_selector "#page-title[value='Elsewhere']", wait: 8

      assert_equal "intro", @section.reload.settings["anchor"]
      assert_equal other.id.to_s, find("[data-tree-open-page]", visible: :all)["data-tree-open-page"]
    end
  end

  # ---- Nothing typed in the rail is lost ----

  RELOAD_LATER = "Something on this page changed elsewhere. Reload once your unsaved text is safe.".freeze
  CLAIM = '/editing/(page|post)/\\d+/claim(\\?.*)?$'.freeze
  LIVE = 8

  def anchor_field(section = @section) = "#block-#{section.id}-anchor"

  # Marks the rail's region, so a test can tell it is the same element later.
  def mark_region(section = @section) = page.execute_script("document.querySelector(#{settings_region(section).to_json}).__same = true")

  def same_region?(section = @section) = page.evaluate_script("document.querySelector(#{settings_region(section).to_json}).__same === true")

  def delay_next(verb, source)
    page.execute_script(<<~JS, verb, source)
      const [ verb, source ] = arguments
      let spent = false
      const real = window.fetch
      window.fetch = function (input, init = {}) {
        const url = typeof input === "string" ? input : input.url
        const method = String(init.method || "GET").toUpperCase()
        if (!spent && method === verb && new RegExp(source).test(url)) {
          spent = true
          const args = arguments
          return new Promise((resolve) => { window.__delayed = () => resolve(real.apply(window, args)) })
        }
        return real.apply(this, arguments)
      }
    JS
  end

  def await_delayed = assert_eventually(wait: LIVE, message: "the delayed request never reached the page's fetch") { page.evaluate_script("typeof window.__delayed === 'function'") }

  def send_delayed = page.execute_script("window.__delayed(); window.__delayed = null")

  # An anchor typed into the rail's region whose save never goes: what a
  # deleted section's region holds when its colleague's delete arrives.
  def type_unsent(text, section = @section)
    form = "#section-#{section.id}-form".to_json
    page.execute_script("const a = window.Stimulus.getControllerForElementAndIdentifier(document.querySelector(#{form}), 'admin--saving--autosave'); a.saveNow = () => {}")
    find(anchor_field(section)).send_keys(text)
    page.execute_script("const a = window.Stimulus.getControllerForElementAndIdentifier(document.querySelector(#{form}), 'admin--saving--autosave'); clearTimeout(a.timer); a.timer = null")
  end

  test "a refused move with text typed in the rail while it was out does not redraw the list, and the text is saved on its base" do
    at_window(WIDE) do
      open_docked
      open_anchor
      find(anchor_field).send_keys("intro")
      ContentBlock.where(id: @left.id).update_all(section_column: 2, position: 1) # version: none (a test's own stale screen)
      # The anchor's edit is sent ahead of the move (`sendHeldEdits` counts the rail's forms); the move is held.
      script_writes("pass", "hold")

      drop_into(@left, "#content-blocks-list")
      await_js "typeof window.__release[1] === 'function'"
      assert_includes page.evaluate_script("window.__writes[0]"), "/content_blocks/#{@section.id}", "the rail's edit was not sent ahead of the move"
      mark_region
      find(anchor_field).send_keys("-more")
      page.execute_script("window.__release[1]()")

      assert_selector "#content-blocks-alert", text: ContentBlocks::Reorder::STALE
      assert_selector "#content-blocks-alert", text: RELOAD_LATER
      assert same_region?, "the rail's region was replaced"
      assert_one_region
      assert_selector in_rail, visible: :visible
      assert_equal "intro-more", find(anchor_field).value
      page.execute_script("document.activeElement.blur()")
      assert_writes_settled
      assert_equal "intro-more", @section.reload.settings["anchor"]
      assert_no_text "Changed elsewhere"
    end
  end

  test "a reorder's Undo while the rail holds text inside its debounce keeps the region, and the text is saved on its base" do
    at_window(WIDE) do
      open_docked
      find("#{card_of(@second)} button[aria-label='Section actions']").click
      click_button "Move up"
      assert_selector "#toasts .admin-toast[data-kind=undo]", wait: 10
      assert_writes_settled

      open_anchor
      mark_region
      find(anchor_field).send_keys("intro")
      within("#toasts") { press "Undo" }

      assert_selector "#toasts .admin-toast", text: /Order restored/, wait: 10
      assert_equal [ @section.id, @second.id ], cards_in_list
      assert same_region?, "the rail's region was replaced by the redrawn card's"
      assert_one_region
      assert_selector in_rail, visible: :visible
      assert_selector "#{card_of(@section)}[data-chosen]"
      assert_equal "intro", find(anchor_field).value
      assert_writes_settled
      assert_equal "intro", @section.reload.settings["anchor"]
      assert_no_text "Changed elsewhere"
    end
  end

  # A 409 and a refused move have one cause, a second editor on the page,
  # so the two meet: the paused form's text is the only copy, and the list
  # is not drawn over it.
  test "a 409-paused anchor in the rail that meets a refused move keeps its text and its region" do
    at_window(WIDE) do
      open_docked
      open_anchor
      travel 1.minute do
        as_unheard(@dana) { ContentBlocks::Save.call(@section.reload, attributes: { settings: @section.settings.merge("anchor" => "theirs") }) }
      end
      find(anchor_field).send_keys("mine")
      page.execute_script("document.activeElement.blur()")
      assert_selector "#block-#{@section.id}-save-status", text: "CHANGED ELSEWHERE", wait: 8
      mark_region
      ContentBlock.where(id: @left.id).update_all(section_column: 2, position: 1) # version: none (a test's own stale screen)

      drop_into(@left, "#content-blocks-list")

      assert_selector "#content-blocks-alert", text: ContentBlocks::Reorder::STALE
      assert_selector "#content-blocks-alert", text: RELOAD_LATER
      assert same_region?, "the rail's region was replaced"
      assert_one_region
      assert_equal "mine", find(anchor_field).value
      assert_selector "#block-#{@section.id}-save-status", text: "CHANGED ELSEWHERE"
      # Paused, it sends nothing over the colleague's save.
      assert_equal "theirs", @section.reload.settings["anchor"]
    end
  end

  def deleted_strip = "#{in_rail} #block-#{@section.id}-hold [data-editing-kind]"

  def delete_chosen_with_text
    open_docked
    await_notes_live
    open_anchor
    type_unsent("unsaved words")
    as(@dana, channel: :admin) { ContentBlocks::Destroy.call(@section.reload) }
    assert_selector "#{in_rail} [role=alert]", text: "Dana Weiss deleted this block. Your changes weren't saved.", wait: LIVE
  end

  test "a section deleted under unsaved text in the rail keeps its text there, with the notice and its Remove" do
    at_window(WIDE) do
      delete_chosen_with_text

      assert_no_selector card_of(@section)
      assert_selector deleted_strip, visible: :visible
      assert_equal "unsaved words", find(anchor_field).value
      assert_one_region
      within(deleted_strip) { click_button "Remove" }
      assert_no_selector settings_region, visible: :all
      assert_empty_line
    end
  end

  test "Close on a deleted section's region with unsaved text keeps it, with its text" do
    at_window(WIDE) do
      delete_chosen_with_text

      find(close_button).click
      await_frames
      assert_selector in_rail, visible: :visible
      assert_equal "unsaved words", find(anchor_field).value
      keyboard.type(:escape)
      await_frames
      assert_selector in_rail, visible: :visible
      assert_selector deleted_strip, visible: :visible
    end
  end

  test "an undock with a deleted section's region holding text keeps it in sight in the blocks column" do
    at_window(WIDE) do
      delete_chosen_with_text

      page.current_window.resize_to(NARROW, 900)
      assert_docked(false)
      assert_selector ".admin-content-blocks #{settings_region}", visible: :visible
      assert_one_region
      assert_equal "unsaved words", find(anchor_field).value
      assert_selector "#block-#{@section.id}-hold [data-editing-kind]", visible: :visible
      within("#block-#{@section.id}-hold [data-editing-kind]") { click_button "Remove" }
      assert_no_selector settings_region, visible: :all
    end
  end

  test "a section deleted while its region in the rail is clean takes the region with it" do
    at_window(WIDE) do
      open_docked
      await_notes_live
      open_anchor

      as(@dana, channel: :admin) { ContentBlocks::Destroy.call(@section.reload) }

      assert_no_selector card_of(@section), wait: LIVE
      assert_no_selector settings_region, visible: :all
      assert_empty_line
    end
  end

  # A hold's reveal (`admin--editing--hold#reveal`) shows a frozen form with
  # no field: it is not a press, so the rail stays where the person is.
  test "a section's lost hold while the person types in the page settings leaves the Page panel, the focus and the text" do
    at_window(WIDE) do
      open_docked
      await_notes_live
      find(word("background")).click
      delay_next("POST", CLAIM)
      find("#block-#{@section.id}-background").find("option[value=tinted]").select_option
      await_delayed
      # The select keeps the press for itself while it has the focus.
      page.execute_script("document.activeElement.blur()")
      find(close_button).click
      assert_selector at_home, visible: :hidden
      assert_selector "#editor-grid-tab-page[aria-selected=true]"
      Editing::Reservation.claim(subject: @section, record: @page, user: @dana, tab: "tab-dddddddd")
      find("#page-title").click
      find("#page-title").send_keys(" now")

      send_delayed

      assert_selector "#block-#{@section.id}-hold [data-editing-kind=lost]", wait: LIVE
      assert_selector "#{at_home} form[data-editing-frozen=true]", visible: :visible
      assert_selector "#editor-grid-tab-page[aria-selected=true]"
      assert_selector "#page-settings", visible: :visible
      assert focus_is_on("#page-title"), "the focus left the title"
      assert_equal "Landing now", find("#page-title").value
      assert_no_selector "[data-chosen]"
    end
  end

  test "a held section chosen in the rail shows its selection" do
    Editing::Reservation.claim(subject: @section, record: @page, user: @dana, tab: "tab-bbbbbbbb", now: Time.current)
    at_window(WIDE) do
      open_docked
      find(word("width")).click
      assert_selector "#{card_of(@section)}[data-chosen][data-card-edge=held]"
      outline = page.evaluate_script("(() => { const style = getComputedStyle(document.querySelector(#{card_of(@section).to_json})); return [ style.outlineStyle, style.outlineWidth, style.outlineOffset, style.outlineColor ] })()")
      accent = page.evaluate_script("(() => { const probe = document.createElement('span'); probe.style.color = 'var(--cs-accent)'; document.body.append(probe); const colour = getComputedStyle(probe).color; probe.remove(); return colour })()")
      assert_equal [ "solid", "2px", "2px", accent ], outline
    end
  end

  def asks_before_unload?
    page.evaluate_script(<<~JS)
      (() => {
        const event = new Event("beforeunload", { cancelable: true })
        window.dispatchEvent(event)
        return event.defaultPrevented
      })()
    JS
  end
end
