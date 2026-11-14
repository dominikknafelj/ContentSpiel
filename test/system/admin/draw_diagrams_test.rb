require "application_system_test_case"

# The Draw diagrams screen's run in a browser (draw-diagrams spec §5, the
# Design System's StudioDrawDiagrams): `admin--diagram--draw-all` opens one
# renderer frame, draws each listed diagram in turn, saves each drawing
# through the write queue (`Admin::DiagramDrawingsController#update`) and
# writes the rows' states, the summary and the card of live pages.
#
# The saves are counted on the server, by the controller's own
# `process_action` notification, so a request the browser never sent and
# one it sent and the server dropped are never confused. A test that keeps a
# save in flight holds it in the browser (`hold_first_save`), passing every
# other request through untouched.
class Admin::DrawDiagramsSystemTest < ApplicationSystemTestCase
  FLOW = "flowchart LR\n  A[Draft] --> B[Review]".freeze
  FLOW_LIVE = "flowchart LR\n  A[Draft] --> B[Review]\n  B --> C[Live]".freeze
  FLOW_DE = "flowchart LR\n  A[Entwurf] --> B[Prüfung]".freeze
  # Mermaid's parser stops at a broken arrow.
  BROKEN = "flowchart LR\n  A[Draft] --> B[Review]\n  B -- > C".freeze
  OTHER_TAB = "tab-bbbbbbbb".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    users(:one).update!(name: "Olga Braun")
    users(:two).update!(name: "Mira Holt")
    @page = create_page(title: "Flows", published: false)
    @saves = []
    @counter = ActiveSupport::Notifications.subscribe("process_action.action_controller") do |*, payload|
      @saves << payload[:params]["id"] if payload[:controller] == "Admin::DiagramDrawingsController" && payload[:action] == "update"
    end
    sign_in_via_form(users(:one))
  end

  teardown { ActiveSupport::Notifications.unsubscribe(@counter) }

  def diagram(source, page: @page, translations: {})
    result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "diagram" },
      translations: { "en" => { settings: { "source" => source } } }.merge(translations), actor: users(:one))
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  def visit_list = visit_screen(admin_diagram_drawings_path)

  def row(block, locale = "en") = "#draw-#{block.id}-#{locale}"

  def chip(block, locale = "en") = find("#{row(block, locale)} [data-part='state']").text.squish

  def reason(block, locale = "en") = find("#{row(block, locale)} [data-part='reason']", visible: :all).text(:all).squish

  def assert_chip(block, text, locale = "en", wait: 20)
    assert_selector "#{row(block, locale)} [data-part='state']", exact_text: text, wait: wait
  end

  def start_button = find("[data-admin--diagram--draw-all-target='start']", visible: :all)

  def summary = find("[data-admin--diagram--draw-all-target='summary']", visible: :all).text(:all).squish

  def drawing(block, locale = "en") = block.reload.translated_settings.to_h.dig(locale, "drawing")

  def assert_current_drawing(block, source, locale = "en")
    stored = drawing(block, locale)
    assert stored, "no drawing was stored for #{locale}"
    assert Diagrams::Drawing.new(stored).current?(block.translated_settings.dig(locale, "source")), "the drawing is not of the stored source"
    assert_equal Diagrams::Drawing.digest(source), stored["from"]
  end

  # Keeps the first save in the browser until `release_save`; every other
  # request goes through.
  def hold_first_save
    page.execute_script(<<~JS)
      const sent = window.fetch
      window.__held = false
      window.fetch = (url, options = {}) => {
        const write = (options.method || "GET").toUpperCase() === "PATCH" && String(url.url || url).includes("/diagram-drawings/")
        if (!write || window.__held) return sent(url, options)
        window.__held = true
        return new Promise((resolve, reject) => { window.__releaseSave = () => sent(url, options).then(resolve, reject) })
      }
    JS
  end

  def await_held_save = await_js("window.__held === true", wait: 20, message: "the first save was never sent")

  def release_save = page.execute_script("window.__releaseSave()")

  test "draw all draws and saves every row" do
    first = diagram(FLOW)
    second = diagram(FLOW_LIVE)
    visit_list
    assert_selector "[data-draw-frame] iframe[tabindex='-1']", visible: :all
    slot = find("[data-draw-frame]", visible: :all)
    assert_equal "true", slot["aria-hidden"]
    assert_not_equal "none", page.evaluate_script("getComputedStyle(arguments[0]).display", slot), "the frame lays out, so Mermaid can measure"

    press "Draw all"
    assert_chip first, "Drawn"
    assert_chip second, "Drawn"

    assert_equal "2 drawn.", summary
    assert_current_drawing first, FLOW
    assert_current_drawing second, FLOW_LIVE
    assert_equal 2, @saves.size
    assert_no_selector "button", text: "Draw all", wait: 0
    assert_no_selector "[aria-busy='true'][data-draw-row]"
    assert_equal "2 drawn.", find("[data-admin--diagram--draw-all-target='status']", visible: :all).text(:all).squish, "the live region speaks the end"
  end

  # One block's rows in two languages share its base: the first save moves
  # it, and the second is sent on the base that save answered.
  test "a block's two languages are both drawn" do
    block = diagram(FLOW, translations: { "de" => { settings: { "source" => FLOW_DE } } })
    visit_list

    press "Draw all"
    assert_chip block, "Drawn", "en"
    assert_chip block, "Drawn", "de"

    assert_current_drawing block, FLOW, "en"
    assert_current_drawing block, FLOW_DE, "de"
    assert_equal "2 drawn.", summary
  end

  test "a source that does not draw is reported and the run goes on" do
    broken = diagram(BROKEN)
    fine = diagram(FLOW)
    visit_list

    press "Draw all"
    assert_chip fine, "Drawn"
    assert_chip broken, "Doesn't draw", wait: 0
    assert_match(/\AThis diagram doesn't draw: .+/, reason(broken))
    assert_equal "danger", find("#{row(broken)} [data-part='reason']")["data-tone"]

    assert_nil drawing(broken)
    assert_current_drawing fine, FLOW
    assert_equal [ fine.id.to_s ], @saves, "a source that doesn't draw sends nothing"
    assert_equal "1 drawn · 1 doesn't draw.", summary
    assert_selector "button", exact_text: "Draw all", wait: 0
  end

  test "a held block is skipped with the holder" do
    held = diagram(FLOW)
    fine = diagram(FLOW_LIVE)
    reserve(held, @page, users(:two), OTHER_TAB)
    visit_list

    press "Draw all"
    assert_chip fine, "Drawn"
    assert_chip held, "Skipped", wait: 0
    assert_equal "Being edited by #{PersonName.of(users(:two))}.", reason(held)
    assert_nil find("#{row(held)} [data-part='reason']")["data-tone"]

    assert_nil drawing(held)
    assert_equal "1 drawn · 1 skipped.", summary
  end

  test "a live page is offered for review and publish" do
    live = create_page(title: "Live flows", published: true)
    block = diagram(FLOW, page: live)
    publish_changes(live)
    copies = Publishing::Version.of(live).pluck(:id, :blocks)
    draft_block = diagram(FLOW_LIVE)
    visit_list
    assert_no_selector "[data-admin--diagram--draw-all-target='publish']"

    press "Draw all"
    assert_chip block, "Drawn"
    assert_chip draft_block, "Drawn"

    within "[data-admin--diagram--draw-all-target='publish']" do
      assert_selector "h2", exact_text: "Live pages with new drawings"
      assert_selector "li", count: 1
      assert_selector "[data-part='title']", exact_text: "Live flows"
      link = find("a", exact_text: "Review and publish…")
      assert_equal admin_page_path(live, review: "publish"), URI(link[:href]).request_uri
    end
    assert_equal copies, Publishing::Version.of(live).pluck(:id, :blocks), "nothing is published"
    assert live.reload.unpublished_changes?
  end

  test "stop ends after the row in hand" do
    first = diagram(FLOW)
    second = diagram(FLOW_LIVE)
    visit_list
    hold_first_save

    press "Draw all"
    await_held_save
    assert_chip first, "Drawing…", wait: 0
    assert_equal "true", find(row(first))["aria-busy"]
    press "Stop"
    assert_selector "button[disabled][aria-busy='true']", exact_text: "Stopping…"

    release_save
    assert_chip first, "Drawn"
    assert_chip second, "Skipped"
    assert_equal "Stopped before it was drawn.", reason(second)
    assert_equal "1 drawn · 1 skipped.", summary
    assert_equal [ first.id.to_s ], @saves
    assert_nil drawing(second)
    assert_selector "button:not([disabled])", exact_text: "Draw all"
  end

  test "leaving mid-run sends nothing more" do
    first = diagram(FLOW)
    second = diagram(FLOW_LIVE)
    visit_list
    hold_first_save

    press "Draw all"
    await_held_save
    watch_frame_load
    click_link "Dashboard"
    release_save
    await_frame_load
    assert_no_selector "[data-controller~='admin--diagram--draw-all']"

    assert_eventually(message: "the save in flight never arrived") { @saves.size == 1 }
    sleep 1 # sleep: a second save would follow the first by one draw; nothing marks that it did not
    assert_equal [ first.id.to_s ], @saves
    assert_current_drawing first, FLOW
    assert_nil drawing(second)
  end

  test "the frame is taken back before cache" do
    first = diagram(BROKEN)
    second = diagram(FLOW)
    live = create_page(title: "Live flows", published: true)
    third = diagram(FLOW_LIVE, page: live)
    visit_list
    press "Draw all"
    assert_chip second, "Drawn"
    assert_chip third, "Drawn"
    assert_selector "[data-admin--diagram--draw-all-target='publish']"

    page.execute_script("document.dispatchEvent(new Event('turbo:before-cache'))")
    assert_no_selector "iframe", visible: :all
    assert_no_selector "[data-draw-frame]", visible: :all
    [ first, second, third ].each { |block| assert_chip block, "Not drawn yet", wait: 0 }
    assert_equal "", reason(first)
    assert_no_selector "[data-draw-row] [data-part='reason']:not([hidden])"
    assert_no_selector "[data-admin--diagram--draw-all-target='publish']"
    assert_equal 0, page.evaluate_script("document.querySelector(\"[data-admin--diagram--draw-all-target='publishList']\").children.length")
    assert_equal "", summary
    assert_equal "", find("[data-admin--diagram--draw-all-target='status']", visible: :all).text(:all)
    assert_no_selector "[data-admin--diagram--draw-all-target='progress']"
    assert_equal "Draw all", start_button.text
    assert_not start_button.disabled?
    assert_equal Admin::Ui::ButtonComponent.classes(:primary), start_button[:class]
  end
end
