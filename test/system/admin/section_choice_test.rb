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
