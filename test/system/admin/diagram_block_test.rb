require "application_system_test_case"

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

  test "a classDef line is refused with its line's sentence" do
    block = diagram_of
    visit_editor(@page)
    paste_source(block, FLOW)
    await_stored_drawing(block, FLOW)

    paste_source(block, "#{FLOW}\n  classDef done fill:#0f0")
    assert_selector "#{field_selector(block)} [data-admin--diagram--preview-target='status']",
      text: "Line 3: colours come from the site's theme, so classDef isn't used here.", wait: 10
    assert_selector "#{field_selector(block)} [data-admin--diagram--preview-target='status'] code", exact_text: "classDef"
    assert_includes status_text(block), "The site keeps the last drawing that worked."

    assert_equal 2, marked_line(block), "the mark stands on the third line"

    # Typed on with the same refusal, the region is not written again.
    page.execute_script(<<~JS, field_selector(block))
      const region = document.querySelector(arguments[0] + " [data-admin--diagram--preview-target='status']")
      window.__statusWrites = 0
      new MutationObserver((records) => { window.__statusWrites += records.length }).observe(region, { childList: true, subtree: true, characterData: true })
    JS
    paste_source(block, "#{FLOW}\n  classDef done fill:#0f0\n")
    paste_source(block, "#{FLOW}\n  classDef done fill:#0f0\n  ")
    # The source's autosave is the form's ordinary 422 (the server holds the
    # same line rules); its answer is the end of the window.
    assert_selector "##{source_id(block)}-errors", text: "Line 3: colours come from the site's theme", wait: 10
    await_frames
    assert_equal 0, page.evaluate_script("window.__statusWrites"), "the same error is said once"
    assert_equal Diagrams::Drawing.digest(FLOW), stored(block).dig("drawing", "from")
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
end
