require "application_system_test_case"
require_relative "../../support/diagram_fixtures"

# The Diagram block's card in the page editor, in a browser (Diagram block
# spec §2 and §7, the Design System's EditorDiagramBlock and
# EditorDiagramError): `admin--diagram--preview` builds the sandboxed
# renderer frame, posts the source to it as it is typed, writes the drawing
# that comes back into the hidden drawing field so that the card's autosave
# stores source and drawing together, and shows the preview's states.
#
# The suite's Chrome runs with `--disable-web-security`, under which this
# page can read the frame's document: `frame_text` reads what the frame
# shows. The frame's origin wall is `diagram_renderer_test.rb`'s.
class Admin::DiagramBlockSystemTest < ApplicationSystemTestCase
  FLOW = "flowchart LR\n  A[Draft] --> B[Review]".freeze
  FLOW_LIVE = "flowchart LR\n  A[Draft] --> B[Review]\n  B --> C[Live]".freeze
  # Mermaid's parser stops at a broken arrow.
  BROKEN = "flowchart LR\n  A[Draft] --> B[Review]\n  B -- > C".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    users(:one).update!(name: "Olga Braun")
    @page = create_page(title: "Docs", published: false)
    sign_in_via_form(users(:one))
  end

  def diagram_of(translations = {})
    @page.content_blocks.create!(block_type: "diagram", position: @page.content_blocks.count, translated_settings: translations)
  end

  def field_selector(block) = "#content_block_#{block.id} [data-controller~='admin--diagram--preview']"

  def source_id(block) = "block-#{block.id}-source"

  # Puts `text` into the source as a paste would: one `input` event.
  def paste_source(block, text)
    page.execute_script("const field = document.getElementById(arguments[0]); field.value = arguments[1]; field.dispatchEvent(new Event('input', { bubbles: true }))", source_id(block), text)
  end

  def drawing_value(block) = page.evaluate_script("document.getElementById(arguments[0]).value", "block-#{block.id}-drawing")

  def frames(block) = page.evaluate_script("document.querySelectorAll(arguments[0] + ' iframe').length", field_selector(block))

  # What the frame shows: the text of its drawing, "" while it shows none.
  def frame_text(block)
    page.evaluate_script(<<~JS, field_selector(block))
      (() => {
        const frame = document.querySelector(arguments[0] + " iframe")
        const shown = frame && frame.contentDocument && frame.contentDocument.querySelector("#diagram > svg")
        return shown ? shown.textContent : ""
      })()
    JS
  end

  def await_frame_text(block, text, message: "the frame never drew #{text}")
    assert_eventually(wait: 15, message: message) { frame_text(block).include?(text) }
  end

  # Which line of the source the band stands on, 0 the first, in the
  # well's own line height; nil while none is shown.
  def marked_line(block)
    page.evaluate_script(<<~JS, field_selector(block), source_id(block))
      (() => {
        const mark = document.querySelector(arguments[0] + " [data-admin--diagram--preview-target='line']")
        if (!mark || mark.hidden) return null
        const field = document.getElementById(arguments[1])
        const style = getComputedStyle(field)
        const line = (mark.getBoundingClientRect().top - field.getBoundingClientRect().top - parseFloat(style.borderTopWidth) - parseFloat(style.paddingTop)) / parseFloat(style.lineHeight)
        return Math.round(line * 100) / 100
      })()
    JS
  end

  def frame_height(block) = page.evaluate_script("Math.round(document.querySelector(arguments[0] + ' iframe').getBoundingClientRect().height)", field_selector(block))

  def status_text(block) = find("#{field_selector(block)} [data-admin--diagram--preview-target='status']", visible: :all).text(:all).squish

  def stored(block, locale: "en") = block.reload.translated_settings.to_h.fetch(locale, {})

  def await_stored_drawing(block, source, locale: "en")
    from = Diagrams::Drawing.digest(source)
    assert_eventually(wait: 15, message: "no drawing of #{source.inspect} was stored") do
      values = stored(block, locale: locale)
      values["source"] == source && values.dig("drawing", "from") == from
    end
  end

  test "typing a flowchart draws it in the frame and autosave stores source and drawing together" do
    block = diagram_of
    visit_editor(@page)
    assert_equal 1, frames(block)
    assert_equal "Diagram preview", find("#{field_selector(block)} iframe")["title"]
    assert_equal "allow-scripts", find("#{field_selector(block)} iframe")["sandbox"]
    assert_selector "#{field_selector(block)} [data-admin--diagram--preview-target='blank']", exact_text: "Type a diagram to see it drawn."

    find("##{source_id(block)}").set(FLOW)
    await_frame_text(block, "Review")
    assert_no_selector "#{field_selector(block)} [data-admin--diagram--preview-target='blank']"

    await_stored_drawing(block, FLOW)
    drawing = stored(block)["drawing"]
    assert_includes drawing["svg"], "Review"
    assert Diagrams::Drawing.new(drawing).current?(stored(block)["source"])
    assert_equal drawing["from"], JSON.parse(drawing_value(block))["from"], "the hidden field holds what was stored"
    assert_equal "", status_text(block), "a drawing that worked says nothing"
  end

  # The digest is of the source as the server casts it: CRLF made LF and the
  # outer blank lines dropped, so the drawing is current for what is stored.
  test "a source typed with blank lines around it stores a drawing current for the stored source" do
    block = diagram_of
    visit_editor(@page)

    paste_source(block, "\n\n#{FLOW}\n\n  \n")
    await_frame_text(block, "Review")

    await_stored_drawing(block, FLOW)
    assert Diagrams::Drawing.new(stored(block)["drawing"]).current?(stored(block)["source"])
  end

  test "the stored drawing survives a reload and opening the card saves nothing" do
    block = diagram_of
    visit_editor(@page)
    paste_source(block, FLOW)
    await_stored_drawing(block, FLOW)
    assert_writes_settled
    saved = stored(block)
    updated_at = block.reload.updated_at
    events = Audit::Event.count

    visit_editor(@page)
    await_frame_text(block, "Review")
    assert_equal saved["drawing"], JSON.parse(drawing_value(block))
    await_frames
    assert_writes_settled

    assert_equal updated_at, block.reload.updated_at, "opening the card wrote nothing"
    assert_equal events, Audit::Event.count
    assert_equal "", status_text(block)
  end

  test "a parse error keeps the last drawing and says so" do
    block = diagram_of
    visit_editor(@page)
    paste_source(block, FLOW_LIVE)
    await_stored_drawing(block, FLOW_LIVE)

    paste_source(block, BROKEN)
    assert_selector "#{field_selector(block)} [data-admin--diagram--preview-target='status'] [role]", count: 0, visible: :all, wait: 10
    assert_selector "#{field_selector(block)} [data-admin--diagram--preview-target='status'] .border-warn", text: "This diagram doesn't draw:", wait: 10
    assert_includes status_text(block), "The site keeps the last drawing that worked."
    # Mermaid's message as it writes it, which counts its lines its own way.
    assert_selector "#{field_selector(block)} [data-admin--diagram--preview-target='status'] pre", text: "Parse error on line"
    assert_selector "#{field_selector(block)} [data-admin--diagram--preview-target='kept']", exact_text: "Last drawing that worked"
    assert_includes frame_text(block), "Live", "the frame keeps the drawing that worked"
    assert_equal 2, marked_line(block), "the line Mermaid names, the third, is marked"

    assert_writes_settled
    assert_equal BROKEN, stored(block)["source"], "the text is saved as typed"
    assert_equal Diagrams::Drawing.digest(FLOW_LIVE), stored(block).dig("drawing", "from"), "and the drawing that worked is kept"

    # Drawing again takes the error, the badge and the line's mark away.
    paste_source(block, FLOW)
    assert_no_selector "#{field_selector(block)} [data-admin--diagram--preview-target='kept']", wait: 10
    assert_equal "", status_text(block)
    assert_nil marked_line(block)
    await_stored_drawing(block, FLOW)
  end

  test "a parse error with nothing drawn yet says so in the frame and the notice" do
    block = diagram_of
    visit_editor(@page)

    paste_source(block, BROKEN)
    assert_selector "#{field_selector(block)} [data-admin--diagram--preview-target='status']", text: "This diagram doesn't draw:", wait: 10
    assert_includes status_text(block), "Nothing is drawn yet."
    assert_selector "#{field_selector(block)} [data-admin--diagram--preview-target='blank']", exact_text: "Nothing is drawn yet."
    assert_no_selector "#{field_selector(block)} [data-admin--diagram--preview-target='kept']"
    assert_writes_settled
    assert_nil stored(block)["drawing"]
  end

  # A refused line is the card's to say and never a refused save: the
  # source is stored as typed and the drawing stays the last that worked.
  test "a classDef line is said with its line's sentence, its source saved with no field error, its drawing kept" do
    block = diagram_of
    visit_editor(@page)
    paste_source(block, FLOW)
    await_stored_drawing(block, FLOW)

    refused = "#{FLOW}\n  classDef done fill:#0f0"
    paste_source(block, refused)
    assert_selector "#{field_selector(block)} [data-admin--diagram--preview-target='status']",
      text: "Line 3: colours come from the site's theme, so classDef isn't used here.", wait: 10
    assert_selector "#{field_selector(block)} [data-admin--diagram--preview-target='status'] code", exact_text: "classDef"
    assert_includes status_text(block), "The site keeps the last drawing that worked."
    assert_equal 2, marked_line(block), "the mark stands on the third line"

    assert_eventually(wait: 10, message: "the refused source was never saved") { stored(block)["source"] == refused }
    assert_writes_settled
    assert_equal "", find("##{source_id(block)}-errors", visible: :all).text(:all).strip, "no field error"
    assert_equal Diagrams::Drawing.digest(FLOW), stored(block).dig("drawing", "from"), "the drawing that worked is kept"

    # Typed on with the same refusal, the region is not written again.
    page.execute_script(<<~JS, field_selector(block))
      const region = document.querySelector(arguments[0] + " [data-admin--diagram--preview-target='status']")
      window.__statusWrites = 0
      new MutationObserver((records) => { window.__statusWrites += records.length }).observe(region, { childList: true, subtree: true, characterData: true })
    JS
    paste_source(block, "#{refused}\n")
    paste_source(block, "#{refused}\n  ")
    assert_eventually(wait: 10) { stored(block)["source"] == refused } # the cast drops the outer blank lines
    assert_writes_settled
    await_frames
    assert_equal 0, page.evaluate_script("window.__statusWrites"), "the same error is said once"
  end

  # The frame takes its drawing's height, between 200 and 640 pixels, so a
  # pie is shown whole.
  test "the frame is as high as its drawing" do
    block = diagram_of
    visit_editor(@page)
    assert_equal 200, frame_height(block)

    paste_source(block, DiagramFixtures.sources.fetch("pie"))
    await_frame_text(block, "English")
    assert_eventually(wait: 5, message: "the frame never grew") { frame_height(block) > 200 }
    height = frame_height(block)
    assert_operator height, :<=, 640
    assert page.evaluate_script(<<~JS, field_selector(block)), "the frame shows its drawing with no scroll"
      (() => {
        const frame = document.querySelector(arguments[0] + " iframe")
        const root = frame.contentDocument.documentElement
        return root.scrollHeight <= root.clientHeight + 1
      })()
    JS

    paste_source(block, "")
    assert_eventually(wait: 10, message: "the frame never went back to its least height") { frame_height(block) == 200 }
  end

  # A stored drawing whose source no longer draws (a source changed and
  # saved while it did not draw) is what the site shows, and the card shows
  # it too, under the badge, beside a notice that says it is kept.
  test "a card whose source fails at connect shows the stored drawing as the last that worked" do
    drawing = BlockTypes::Diagram.sample_drawing("en")
    block = diagram_of("en" => { "source" => BROKEN, "drawing" => drawing })
    visit_editor(@page)

    await_frame_text(block, "Published")
    assert_selector "#{field_selector(block)} [data-admin--diagram--preview-target='kept']", exact_text: "Last drawing that worked", wait: 10
    assert_selector "#{field_selector(block)} [data-admin--diagram--preview-target='status']", text: "This diagram doesn't draw:"
    assert_includes status_text(block), "The site keeps the last drawing that worked."
    assert_no_selector "#{field_selector(block)} [data-admin--diagram--preview-target='blank']"
    assert_writes_settled
    assert_equal drawing["from"], stored(block).dig("drawing", "from"), "opening the card wrote nothing"
  end

  # The badge and the notice's last line both follow what the site keeps:
  # a picture drawn at connect that was never stored is not "the last
  # drawing that worked".
  test "a source with no stored drawing whose first edit fails says nothing is drawn yet, with no badge" do
    block = diagram_of("en" => { "source" => FLOW })
    visit_editor(@page)
    await_frame_text(block, "Review")

    paste_source(block, BROKEN)
    assert_selector "#{field_selector(block)} [data-admin--diagram--preview-target='status']", text: "This diagram doesn't draw:", wait: 10
    assert_includes status_text(block), "Nothing is drawn yet."
    assert_not_includes status_text(block), "The site keeps"
    assert_no_selector "#{field_selector(block)} [data-admin--diagram--preview-target='kept']"
    assert_writes_settled
    assert_nil stored(block)["drawing"]
  end

  # A card moved in the document disconnects and connects the same element
  # (a drop, Move up/down): an edit still inside its debounce is drawn and
  # written after it, not dropped. The field is taken out and put back by
  # script, which is the same disconnect and connect without a move's
  # requests.
  test "an edit pending when the card reconnects is drawn and written after it" do
    block = diagram_of
    visit_editor(@page)
    page.execute_script(<<~JS, field_selector(block), source_id(block), FLOW)
      const [selector, id, source] = arguments
      const element = document.querySelector(selector)
      const field = document.getElementById(id)
      field.value = source
      field.dispatchEvent(new Event("input", { bubbles: true }))
      const [parent, next] = [element.parentNode, element.nextSibling]
      element.remove()
      setTimeout(() => parent.insertBefore(element, next), 50)
    JS

    await_frame_text(block, "Review")
    await_stored_drawing(block, FLOW)
  end

  test "while the description is blank a note under the preview says the site shows nothing" do
    block = diagram_of("en" => { "source" => FLOW })
    visit_editor(@page)
    note = "#{field_selector(block)} [data-admin--diagram--preview-target='undescribed']"

    assert_selector "#{note}[role='note']", exact_text: "The site shows this diagram once it has a description."
    find("#block-#{block.id}-description").set("A draft goes to review.")
    assert_no_selector note
    find("#block-#{block.id}-description").set("  ")
    assert_selector note
  end

  test "a type that isn't supported names the list" do
    block = diagram_of
    visit_editor(@page)

    paste_source(block, "mindmap\n  root")
    assert_selector "#{field_selector(block)} [data-admin--diagram--preview-target='status']",
      text: "mindmap diagrams aren't supported yet. Use one of: flowchart, sequenceDiagram, classDiagram, stateDiagram, erDiagram, gantt, pie.", wait: 10
  end

  test "a card held by someone else draws and writes nothing" do
    block = diagram_of("en" => { "source" => FLOW })
    reserve(block, @page, users(:two), "tab-dana-0001")
    visit_editor(@page)

    assert_selector "##{source_id(block)}[readonly]"
    await_frame_text(block, "Review")
    assert_no_selector "#content_block_#{block.id} [data-action*='admin--diagram--preview']"
    await_frames
    assert_writes_settled
    assert_equal "", drawing_value(block)
    assert_nil stored(block)["drawing"]
  end

  test "the translation tab starts from the default's source and stores nothing until the first change" do
    block = diagram_of("en" => { "source" => FLOW })
    visit_editor(@page, locale: "de")

    assert_selector "textarea##{source_id(block)}:not([name])"
    assert_equal FLOW, find("##{source_id(block)}").value
    await_frame_text(block, "Review")
    assert_writes_settled
    assert_empty stored(block, locale: "de")

    german = "flowchart LR\n  A[Entwurf] --> B[Prüfung]"
    paste_source(block, german)
    assert_selector "textarea##{source_id(block)}[name='block[settings][source]']"
    await_frame_text(block, "Prüfung")
    await_stored_drawing(block, german, locale: "de")
    assert_equal FLOW, stored(block)["source"], "the default's source is its own"
  end

  # The latest-id rule: an answer is taken only from the card's own frame,
  # from the opaque origin, for the last source it posted.
  test "a draw answered late for an older keystroke is ignored" do
    block = diagram_of
    visit_editor(@page)
    page.execute_script(<<~JS, field_selector(block))
      const frame = document.querySelector(arguments[0] + " iframe")
      window.__frame = frame
      window.__ids = []
      frame.contentWindow.addEventListener("message", (event) => { if (event.data && "id" in event.data) window.__ids.push(event.data.id) })
    JS
    paste_source(block, FLOW)
    await_stored_drawing(block, FLOW)
    assert_writes_settled
    kept = drawing_value(block)

    page.execute_script(<<~JS)
      const latest = Math.max(...window.__ids)
      const forged = (id, extra = {}) => window.dispatchEvent(new MessageEvent("message", { data: { id, svg: "<svg xmlns='http://www.w3.org/2000/svg'><text>Forged</text></svg>", bytes: 1, elements: 2 }, origin: "null", source: window.__frame.contentWindow, ...extra }))
      forged(latest - 1)
      forged(latest, { origin: window.location.origin })
      forged(latest, { source: window })
    JS
    await_frames
    assert_writes_settled
    assert_equal kept, drawing_value(block)
    assert_not_includes stored(block).dig("drawing", "svg"), "Forged"
  end

  test "the frame is gone after leaving the editor and none is built on a screen with no Diagram block" do
    block = diagram_of("en" => { "source" => FLOW })
    visit_editor(@page)
    await_frame_text(block, "Review")

    page.execute_script("document.dispatchEvent(new Event('turbo:before-cache'))")
    assert_equal 0, frames(block), "taken back before Turbo keeps a copy"
    assert_no_selector "#{field_selector(block)} [data-admin--diagram--preview-target='kept']"

    plain = create_page(title: "Plain", published: false)
    visit_editor(plain)
    assert_no_selector "iframe", visible: :all
    assert_equal 0, page.evaluate_script("performance.getEntriesByType('resource').filter((entry) => entry.name.includes('diagram-renderer')).length")
  end

  # ----- Import file… -----

  IMPORTS = Rails.root.join("test/fixtures/files/diagrams_import")

  def import_id(block) = "#{source_id(block)}-import"

  def replace_dialog(block) = "##{Admin::Fields::MermaidField.replace_dialog_id(source_id(block))}"

  # Chooses a file in the hidden input, as the picker that Import file… opens would.
  def import_file(block, name)
    attach_file(import_id(block), IMPORTS.join(name).to_s, make_visible: true)
  end

  def import_status(block) = find("#{field_selector(block)} [data-admin--diagram--preview-target='importStatus']", visible: :all)

  def source_value(block) = find("##{source_id(block)}").value

  test "importing a .mmd file fills the source and draws it" do
    block = diagram_of
    visit_editor(@page)
    assert_selector "#content_block_#{block.id} .admin-field__label-row button", exact_text: "Import file…"

    import_file(block, "release-flow.mmd")
    flow = IMPORTS.join("release-flow.mmd").read
    assert_no_selector "#{replace_dialog(block)}[open]", visible: :all
    assert_eventually(message: "the file's text is the source") { source_value(block) == flow }
    await_frame_text(block, "Live")
    await_stored_drawing(block, flow.chomp)
    within(import_status(block)) { assert_selector "p.text-small.text-meta", exact_text: "Imported from release-flow.mmd." }

    find("##{source_id(block)}").send_keys(:end, " ")
    within(import_status(block)) { assert_no_selector "p" }
    assert_empty import_status(block).text(:all), "the next keystroke takes the line away"
  end

  test "a .md file's first mermaid fence is taken" do
    block = diagram_of
    visit_editor(@page)

    import_file(block, "guide.md")
    taken = "flowchart LR\n  Written --> Checked\n  Checked --> Published"
    assert_eventually(message: "the first mermaid fence outside another fence is the source") { source_value(block) == taken }
    await_stored_drawing(block, taken)
    within(import_status(block)) do
      assert_selector "p", exact_text: "Imported from guide.md."
      assert_selector "div.bg-sunken", exact_text: "Only the first diagram in guide.md was imported."
    end
    assert_no_selector "#{field_selector(block)} [data-admin--diagram--preview-target='importStatus'] [role]"
  end

  # A fence may stand up to three spaces in, as CommonMark allows (a list
  # item's); its lines lose that indentation, as CommonMark takes them.
  test "a .md file's mermaid fence indented up to three spaces is taken" do
    block = diagram_of
    visit_editor(@page)

    import_file(block, "indented.md")
    taken = "flowchart LR\n  Asked --> Answered"
    assert_eventually(message: "the indented fence's lines, outdented, are the source") { source_value(block) == taken }
    await_frame_text(block, "Answered")
    within(import_status(block)) { assert_selector "p", exact_text: "Imported from indented.md." }
  end

  test "a file with no Mermaid says so and changes nothing" do
    block = diagram_of("en" => { "source" => FLOW })
    visit_editor(@page)
    await_frame_text(block, "Review")
    updated_at = block.reload.updated_at

    import_file(block, "notes.md")
    within(import_status(block)) { assert_selector ".border-warn", exact_text: "notes.md holds no Mermaid diagram. A .md file needs a ```mermaid fence." }
    assert_no_selector "#{replace_dialog(block)}[open]", visible: :all
    assert_equal FLOW, source_value(block)
    await_frames
    assert_writes_settled
    assert_equal updated_at, block.reload.updated_at, "nothing was saved"
  end

  test "a file too long or not UTF-8 says so and changes nothing" do
    block = diagram_of("en" => { "source" => FLOW })
    visit_editor(@page)
    await_frame_text(block, "Review")

    import_file(block, "big-flow.mmd")
    count = ActiveSupport::NumberHelper.number_to_delimited(IMPORTS.join("big-flow.mmd").read.length)
    within(import_status(block)) { assert_selector ".border-warn", exact_text: "big-flow.mmd is too long: its diagram has #{count} characters, and the limit is 10,000." }
    assert_equal FLOW, source_value(block)

    import_file(block, "latin1.mmd")
    within(import_status(block)) { assert_selector ".border-warn", exact_text: "latin1.mmd couldn't be read. Use a .mmd or .md text file." }
    assert_selector "#{field_selector(block)} [data-admin--diagram--preview-target='importStatus'] .border-warn", count: 1, visible: :all
    assert_equal FLOW, source_value(block)
    assert_no_selector "#{replace_dialog(block)}[open]", visible: :all
    assert_writes_settled
    assert_equal FLOW, stored(block)["source"]
  end

  test "replacing a typed source asks first, and Cancel keeps it" do
    block = diagram_of
    visit_editor(@page)
    find("##{source_id(block)}").set(FLOW)
    await_stored_drawing(block, FLOW)

    import_file(block, "release-flow.mmd")
    dialog = find("#{replace_dialog(block)}[open]")
    assert_equal "Replace the source?", dialog.find("h2, h3").text
    assert_text "The diagram in Source is replaced by the one in release-flow.mmd. The site keeps the last drawing that worked until the new one draws."
    assert_equal "Cancel", page.evaluate_script("document.activeElement.textContent").strip, "destructive: Cancel takes the focus"
    dialog.click_button("Cancel")
    assert_no_selector "#{replace_dialog(block)}[open]", visible: :all
    assert_equal FLOW, source_value(block)
    assert_empty import_status(block).text(:all)
    assert_writes_settled
    assert_equal FLOW, stored(block)["source"]

    import_file(block, "release-flow.mmd")
    find("#{replace_dialog(block)}[open]").click_button("Replace source")
    flow = IMPORTS.join("release-flow.mmd").read
    assert_eventually(message: "confirmed, the file's text is the source") { source_value(block) == flow }
    await_stored_drawing(block, flow.chomp)
    within(import_status(block)) { assert_selector "p", exact_text: "Imported from release-flow.mmd." }
  end

  test "an import on the translation tab becomes that language's own source" do
    block = diagram_of("en" => { "source" => FLOW })
    visit_editor(@page, locale: "de")
    await_frame_text(block, "Review")

    import_file(block, "release-flow.mmd")
    find("#{replace_dialog(block)}[open]").click_button("Replace source")
    flow = IMPORTS.join("release-flow.mmd").read
    assert_selector "textarea##{source_id(block)}[name='block[settings][source]']"
    await_stored_drawing(block, flow.chomp, locale: "de")
    assert_equal FLOW, stored(block)["source"], "the default's source is its own"
  end

  test "a held card draws no Import control" do
    block = diagram_of("en" => { "source" => FLOW })
    reserve(block, @page, users(:two), "tab-dana-0001")
    visit_editor(@page)

    assert_selector "##{source_id(block)}[readonly]"
    assert_no_button "Import file…", visible: :all
    assert_no_selector "#content_block_#{block.id} input[type=file], #{replace_dialog(block)}", visible: :all
  end

  # ---- The tile's picture --------------------------------------------------

  SHOTS = Rails.root.join(".superpowers/sdd/2026-11-13-diagram-block/shots")

  # A fixture drawing of `type`, cleaned as a save stores it.
  def tile_of(section, type, position)
    source = DiagramFixtures.sources.fetch(type)
    drawing = { "svg" => Diagrams::Drawing.clean(DiagramFixtures::DIR.join("#{type}.svg").read).svg, "from" => Diagrams::Drawing.digest(source) }
    @page.content_blocks.create!(block_type: "diagram", section: section, section_column: 1, position: position,
      translated_settings: { "en" => { "source" => source, "drawing" => drawing, "description" => "The #{type} diagram." } })
  end

  # The picture box's inside, the drawing's element and what it draws, in
  # CSS pixels.
  def picture_boxes(block)
    page.evaluate_script(<<~JS, "#block-#{block.id}-tile-summary .admin-block-tile__picture")
      (() => {
        const box = document.querySelector(arguments[0])
        const svg = box.querySelector("svg")
        const style = getComputedStyle(box)
        const outer = box.getBoundingClientRect()
        const inset = (side) => parseFloat(style["border" + side + "Width"]) + parseFloat(style["padding" + side])
        const inside = { left: outer.left + inset("Left"), top: outer.top + inset("Top"), right: outer.right - inset("Right"), bottom: outer.bottom - inset("Bottom") }
        const rect = (r) => ({ left: r.left, top: r.top, right: r.right, bottom: r.bottom, width: r.width, height: r.height })
        const drawn = Array.from(svg.children).filter((child) => child.tagName === "g").map((g) => g.getBoundingClientRect())
          .reduce((all, r) => ({ left: Math.min(all.left, r.left), top: Math.min(all.top, r.top), right: Math.max(all.right, r.right), bottom: Math.max(all.bottom, r.bottom) }),
                  { left: Infinity, top: Infinity, right: -Infinity, bottom: -Infinity })
        return { outer: rect(outer), inside: inside, svg: rect(svg.getBoundingClientRect()), drawn: drawn }
      })()
    JS
  end

  def assert_within(inner, outer, message)
    %w[left top].each { |side| assert_operator inner[side], :>=, outer[side] - 0.5, "#{message}: #{side}" }
    %w[right bottom].each { |side| assert_operator inner[side], :<=, outer[side] + 0.5, "#{message}: #{side}" }
  end

  test "a tile's picture scales a tall and a wide drawing to fit its 112 by 72 box, their aspect kept, in both schemes" do
    section = @page.content_blocks.create!(block_type: "section", position: 0)
    tall = tile_of(section, "class", 0)
    wide = tile_of(section, "flowchart", 1)
    visit_editor(@page)

    { tall => :height, wide => :width }.each do |block, fills|
      boxes = picture_boxes(block)
      assert_equal [ 112, 72 ], [ boxes["outer"]["width"].round, boxes["outer"]["height"].round ], "the box is 112 by 72"
      assert_within boxes["svg"], boxes["inside"], "#{block.id}'s drawing element stands inside the box"
      assert_within boxes["drawn"], boxes["inside"], "#{block.id}'s drawing is all inside the box, never cut"
      inside = { width: boxes["inside"]["right"] - boxes["inside"]["left"], height: boxes["inside"]["bottom"] - boxes["inside"]["top"] }
      drawn = boxes["drawn"][fills == :height ? "bottom" : "right"] - boxes["drawn"][fills == :height ? "top" : "left"]
      assert_operator drawn, :>, inside[fills] * 0.8, "#{block.id}'s drawing is scaled to the box's #{fills}, not shrunk or cropped"
    end

    # The shape at a glance: no words, no arrowheads, 1px strokes at any
    # scale, and a node's box solid in the sunken colour.
    look = page.evaluate_script(<<~JS, "#block-#{wide.id}-tile-summary .admin-block-tile__picture")
      (() => {
        const box = document.querySelector(arguments[0])
        const style = (selector) => { const found = box.querySelector(selector); return found && getComputedStyle(found) }
        const probe = document.createElement("span")
        probe.style.color = "var(--cs-sunken)"
        box.append(probe)
        const sunken = getComputedStyle(probe).color
        probe.remove()
        return {
          text: style("text")?.display, marker: style("[marker-end]")?.markerEnd,
          stroke: style(".node rect")?.vectorEffect, fill: style(".node rect")?.fill, sunken: sunken
        }
      })()
    JS
    assert_equal "none", look["text"], "no words"
    assert_equal "none", look["marker"], "no arrowheads"
    assert_equal "non-scaling-stroke", look["stroke"]
    assert_equal look["sunken"], look["fill"], "a node is solid sunken"

    FileUtils.mkdir_p(SHOTS)
    shots = { "tile" => wide, "tile-wide" => wide, "tile-tall" => tall }
    %w[light dark].each do |theme|
      page.execute_script("document.documentElement.setAttribute('data-theme', arguments[0])", theme)
      assert_selector "html[data-theme='#{theme}']"
      shots.each do |name, block|
        page.save_screenshot(SHOTS.join("#{name}-#{theme}.png").to_s, selector: ".admin-block-tile:has(#block-#{block.id}-tile-summary)")
      end
    end
  end
end
