require "application_system_test_case"

# An open page or post editor shows what someone else saved (live-editing spec
# §3.2, `controllers/admin/editing/live_controller.js`): it hears THAT a block
# or the list changed, fetches that part with a plain GET and merges it around
# every form that holds unsaved text. Two people are two Capybara sessions;
# `await_notes_live` waits for the editor's subscription too (its
# `data-live-part`), so a change caused after it is heard. A colleague's write
# that needs no second browser is made through the service as the other user,
# which signals exactly as a request does, without an origin.
class Admin::EditingLiveSystemTest < ApplicationSystemTestCase
  LIVE = 8

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @me = users(:one).tap { |user| user.update!(name: "Olga Braun") }
    @dana = users(:two).tap { |user| user.update!(name: "Dana Weiss") }
    @page = create_page(title: "Pricing", published: false)
    @block = add_block
    sign_in_via_form(@me)
  end

  teardown do
    page.execute_script("try { window.localStorage.removeItem('cs-notes-open') } catch (error) {}")
    page.driver.browser.page.command("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "no-preference" } ])
  end

  def open_page(path = "/cs-studio/pages/#{@page.id}")
    visit path
    await_notes_live
  end

  def join(name, user, path: "/cs-studio/pages/#{@page.id}")
    using_session(name) do
      sign_in_via_form(user)
      visit path
      await_notes_live
      yield if block_given?
    end
  end

  def add_block(by: nil)
    save = proc { ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" }).record }
    by ? as(by, channel: :admin, &save) : save.call
  end

  def card(block) = "#content_block_#{block.id}"

  def doc(text) = { "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => text } ] } ] }

  def type_in(block, text)
    find("#{card(block)} .ProseMirror").click
    find("#{card(block)} .ProseMirror").send_keys(text)
  end

  # What a colleague does from outside the browser.
  def dana_saves(block, text, locale: "en")
    result = as(@dana, channel: :admin) { ContentBlocks::Save.call(block.reload, translations: { locale => { body: doc(text) } }) }
    assert result.ok?, result.errors.to_sentence
  end

  def server_order = BlockOutline.new(@page.content_blocks.reload).top_level.map(&:id)

  def list_order = page.evaluate_script("Array.from(document.querySelectorAll('#content-blocks-list > [data-block-id]')).map((each) => Number(each.dataset.blockId))")

  def assert_list_current(message = "the list never matched the server's order")
    assert_eventually(wait: LIVE, message: -> { "#{message}: screen #{list_order.inspect}, server #{server_order.inspect}" }) { list_order == server_order }
  end

  # Counts every request to the editing GETs, passing each through. Installed
  # for the page already open; `from_load: true` before the next load.
  COUNTER = <<~JS.freeze
    window.__seen = []
    const real = window.fetch
    window.fetch = function (input) {
      const url = typeof input === "string" ? input : input.url
      if (url.includes("/cs-studio/editing/")) window.__seen.push(url)
      return real.apply(this, arguments)
    }
  JS

  def count_requests = page.execute_script(COUNTER)

  def count_requests_from_load
    id = page.driver.browser.page.command("Page.addScriptToEvaluateOnNewDocument", source: COUNTER)["identifier"]
    yield
  ensure
    page.driver.browser.page.command("Page.removeScriptToEvaluateOnNewDocument", identifier: id) if id
  end

  def requests(pattern) = page.evaluate_script("window.__seen").grep(pattern)

  def blocks_requests = requests(%r{/editing/page/\d+/blocks(\?.*)?\z})

  def record_requests = requests(%r{/editing/page/\d+/record(\?.*)?\z})

  def listen_merged = page.execute_script("window.__merged = []; document.getElementById('editing').addEventListener('admin--editing--live:merged', (event) => window.__merged.push(event.detail.part))")

  def set_value(name, value) = page.execute_script("document.getElementById('editing').setAttribute('data-admin--editing--live-#{name}-value', #{value.to_json})")

  # A form with an unsent edit that no timer will send: unsaved, not outstanding.
  def park(block)
    page.execute_script(<<~JS)
      const form = document.querySelector(#{"#{card(block)} form[data-controller~='admin--saving--autosave']".to_json})
      const autosave = window.Stimulus.getControllerForElementAndIdentifier(form, "admin--saving--autosave")
      autosave.saveNow = () => {}
    JS
  end

  def type_unsent(block, text)
    park(block)
    type_in(block, text)
    page.execute_script(<<~JS)
      const form = document.querySelector(#{"#{card(block)} form[data-controller~='admin--saving--autosave']".to_json})
      const autosave = window.Stimulus.getControllerForElementAndIdentifier(form, "admin--saving--autosave")
      clearTimeout(autosave.timer)
      autosave.timer = null
    JS
    assert_equal false, page.evaluate_script("(() => { const form = document.querySelector(#{"#{card(block)} form[data-controller~='admin--saving--autosave']".to_json}); const a = window.Stimulus.getControllerForElementAndIdentifier(form, 'admin--saving--autosave'); return a.unchanged() })()"), "the form should hold an unsent edit"
  end

  def hide_document
    page.execute_script(<<~JS)
      window.__hidden = true
      Object.defineProperty(document, "hidden", { get: () => window.__hidden, configurable: true })
      Object.defineProperty(document, "visibilityState", { get: () => (window.__hidden ? "hidden" : "visible"), configurable: true })
      document.dispatchEvent(new Event("visibilitychange"))
    JS
  end

  def show_document = page.execute_script("window.__hidden = false; document.dispatchEvent(new Event('visibilitychange'))")

  test "what a colleague types and saves appears in my open editor, with who and when, and my reload is not needed" do
    open_page
    join(:dana, @dana) do
      type_in(@block, "Prices from May")
      assert_writes_settled
    end

    assert_selector "#{card(@block)} .ProseMirror", text: "Prices from May", wait: LIVE
    assert_selector "#{card(@block)} [data-editing-mark]", text: "Updated by Dana Weiss", wait: LIVE
    assert_no_selector "#toasts [role=status], #toasts [role=alert]"
  end

  test "the mark goes after its time, and is gone at once with reduced motion" do
    open_page
    set_value("notice", 300)
    dana_saves(@block, "Prices from May")
    assert_selector "#{card(@block)} [data-editing-mark]", text: "Updated by Dana Weiss", wait: LIVE
    assert_no_selector "[data-editing-mark]", wait: LIVE

    page.driver.browser.page.command("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    set_value("notice", 100)
    listen_merged
    dana_saves(@block, "Prices from June")
    assert_selector "#{card(@block)} .ProseMirror", text: "Prices from June", wait: LIVE
    assert_no_selector "[data-editing-mark]", wait: LIVE
    assert_no_selector ".admin-editing-mark--leaving", visible: :all
  end

  test "my own save draws no mark and fetches nothing" do
    open_page
    count_requests
    type_in(@block, "My own text")
    assert_writes_settled
    await_frames

    assert_equal [], page.evaluate_script("window.__seen")
    assert_no_selector "[data-editing-mark]"
  end

  test "the next save of a refreshed card is saved, not refused as stale" do
    open_page
    dana_saves(@block, "Prices from May")
    assert_selector "#{card(@block)} .ProseMirror", text: "Prices from May", wait: LIVE

    type_in(@block, " and June")
    assert_writes_settled
    assert_no_selector "#changed-elsewhere"
    assert_eventually(message: "the block does not hold both texts") do
      text = ContentBlock.find(@block.id).body.to_json
      text.include?("Prices from May") && text.include?("and June")
    end
  end

  test "an added block appears, a moved one snaps to its place and a deleted one goes, with no mark" do
    second = add_block
    open_page
    assert_equal server_order, list_order

    added = add_block(by: @dana)
    assert_list_current
    assert_includes list_order, added.id

    as(@dana, channel: :admin) { assert ContentBlocks::Reorder.call(@page.reload, [ added.id, @block.id, second.id ]).ok? }
    assert_list_current

    as(@dana, channel: :admin) { assert ContentBlocks::Destroy.call(second.reload).ok? }
    assert_list_current
    assert_no_selector card(second)
    assert_no_selector "[data-editing-mark]"
  end

  test "a card I am typing in is not replaced by a colleague's save of the same block, and my save is then refused as before" do
    open_page
    type_unsent(@block, "My draft")
    page.execute_script("window.__card = document.querySelector(#{card(@block).to_json})")
    listen_merged

    dana_saves(@block, "Their text")
    await_js("window.__merged.length > 0", wait: LIVE)
    await_frames

    assert_equal true, page.evaluate_script("window.__card === document.querySelector(#{card(@block).to_json})"), "the card with unsaved text was replaced"
    assert_selector "#{card(@block)} .ProseMirror", text: "My draft"
    assert_no_selector "#{card(@block)} [data-editing-mark]"

    page.execute_script(<<~JS)
      const form = document.querySelector(#{"#{card(@block)} form[data-controller~='admin--saving--autosave']".to_json})
      window.Stimulus.getControllerForElementAndIdentifier(form, "admin--saving--autosave").trigger()
    JS
    assert_selector "#changed-elsewhere", wait: LIVE
    assert_selector "#{card(@block)} .ProseMirror", text: "My draft"
  end

  test "a block deleted under my unsaved text stays, with my text" do
    second = add_block
    open_page
    type_unsent(@block, "My draft")
    listen_merged

    as(@dana, channel: :admin) { assert ContentBlocks::Destroy.call(@block.reload).ok? }
    await_js("window.__merged.length > 0", wait: LIVE)

    assert_selector "#{card(@block)}[data-editing-gone='true']", wait: LIVE
    assert_selector "#{card(@block)} .ProseMirror", text: "My draft"
    assert_selector card(second)
  end

  test "the settings form takes a colleague's saved subtitle, and mine is saved afterwards although they saved blocks in between" do
    open_page
    as(@dana, channel: :admin) { assert Pages::Save.call(@page.reload, translations: { "en" => { subtitle: "Dana's subtitle" } }).ok? }
    assert_eventually(wait: LIVE, message: "the settings form never took the subtitle") { find_field(id: "page-subtitle", visible: :all).value == "Dana's subtitle" }

    dana_saves(@block, "A block in between")
    assert_selector "#{card(@block)} .ProseMirror", text: "A block in between", wait: LIVE

    fill_in id: "page-subtitle", with: "Olga's subtitle"
    assert_writes_settled
    assert_no_selector "#changed-elsewhere"
    assert_equal "Olga's subtitle", @page.reload.subtitle
  end

  test "a post's form takes a colleague's save" do
    post = create_post(title: "Hello")
    path = "/cs-studio/posts/#{post.id}"
    open_page(path)
    as(@dana, channel: :admin) { assert Posts::Save.call(post.reload, translations: { "en" => { excerpt: "A fresh excerpt" } }).ok? }

    assert_eventually(wait: LIVE, message: "#post-form never showed the excerpt") { find_field(id: "post-excerpt", visible: :all).value == "A fresh excerpt" }
  end

  test "on a translation tab the card of the block is refreshed in that language" do
    with_locales(%w[en de], default: "en")
    open_page("/cs-studio/pages/#{@page.id}?locale=de")
    dana_saves(@block, "Preise ab Mai", locale: "de")

    assert_selector "#{card(@block)} .ProseMirror", text: "Preise ab Mai", wait: LIVE
  end

  test "a hidden tab fetches nothing, and catches up once when it is seen" do
    open_page
    count_requests
    hide_document

    dana_saves(@block, "First")
    dana_saves(@block, "Second")
    added = add_block(by: @dana)
    # The document being hidden, there is nothing on the page to wait for: the
    # signals are heard within the cable's round trip.
    sleep 1 # sleep: nothing on a hidden page changes to wait on; shows that no request is made meanwhile
    assert_equal [], page.evaluate_script("window.__seen")

    show_document
    assert_eventually(wait: LIVE, message: "the hidden tab never caught up") { blocks_requests.size == 1 && record_requests.size == 1 }
    assert_selector "#{card(@block)} .ProseMirror", text: "Second", wait: LIVE
    assert_list_current
    assert_includes list_order, added.id
    await_frames
    assert_equal 1, blocks_requests.size
    assert_equal 1, record_requests.size
  end

  test "a confirmed subscription fetches the list and the record's form once" do
    count_requests_from_load { open_page }
    await_frames

    assert_equal 1, blocks_requests.size
    assert_equal 1, record_requests.size
  end

  test "after the socket drops and comes back the editor catches up" do
    open_page
    page.execute_script("import('@hotwired/turbo-rails').then((turbo) => turbo.cable.getConsumer()).then((consumer) => { window.__consumer = consumer })")
    await_js("Boolean(window.__consumer)")
    page.execute_script("window.__consumer.connection.close()")
    await_js("document.body.dataset.notesLive !== 'connected'", wait: LIVE)

    dana_saves(@block, "While you were away")
    page.execute_script("window.__consumer.connection.open()")

    assert_selector "#{card(@block)} .ProseMirror", text: "While you were away", wait: LIVE
    await_js("document.body.dataset.notesLive === 'connected'", wait: LIVE)
  end

  test "a structure signal that arrives during a drag is drawn after the drop, with the dropped block where it was dropped" do
    second = add_block
    third = add_block
    open_page
    page.execute_script("document.querySelector(arguments[0]).scrollIntoView({ block: 'center' })", card(second))
    centre = lambda do |selector|
      page.evaluate_script("(() => { const r = document.querySelector(arguments[0]).getBoundingClientRect(); return [r.left + r.width / 2, r.top + r.height / 2] })()", selector)
    end
    from_x, from_y = centre.call("#{card(@block)} .admin-block-card__handle")
    _, second_y = centre.call("#{card(second)} .admin-block-card__handle")
    _, third_y = centre.call("#{card(third)} .admin-block-card__handle")
    original = list_order

    mouse = drag_pointer(from_x, from_y, (second_y + third_y) / 2)
    assert_selector "body > .admin-drag-fallback"
    added = add_block(by: @dana)
    await_js("window.Stimulus.getControllerForElementAndIdentifier(document.getElementById('editing'), 'admin--editing--live').owed.has('blocks')", wait: LIVE)
    await_frames
    assert_no_selector card(added)
    assert_equal original.sort, list_order.sort

    await_drag_slot_after(second)
    mouse.up
    assert_writes_settled
    assert_list_current
    assert_includes list_order, added.id
  end

  def await_drag_slot_after(block)
    await_js("(() => { const slot = document.querySelector('#content-blocks-list > .admin-drag-ghost'); return !!slot && slot.previousElementSibling?.dataset.blockId === #{block.id.to_s.to_json} })()", wait: LIVE)
  end

  # The colleague REORDERS rather than adds: a stale screen's reorder that
  # leaves a block out is refused by the server (`ContentBlocks::Reorder::STALE`),
  # which would hide the drawing of an old answer behind the refusal's redraw.
  # Here the move is accepted, and its result differs from the held answer.
  test "an answer fetched before this tab's own write was queued is not drawn" do
    second = add_block
    third = add_block
    open_page
    page.execute_script(<<~JS)
      window.__held = 0
      window.__release = null
      const real = window.fetch
      window.fetch = function (input) {
        const url = typeof input === "string" ? input : input.url
        if (window.__release === null && /\\/editing\\/page\\/\\d+\\/blocks(\\?.*)?$/.test(url)) {
          const answer = real.apply(this, arguments)
          window.__held += 1
          return new Promise((resolve) => { window.__release = () => answer.then(resolve) })
        }
        return real.apply(this, arguments)
      }
    JS
    as(@dana, channel: :admin) { assert ContentBlocks::Reorder.call(@page.reload, [ third.id, @block.id, second.id ]).ok? }
    await_js("window.__held === 1", wait: LIVE)

    find("#{card(second)} button[aria-label='Block actions']").click
    within(card(second)) { press "Move up" }
    page.execute_script("window.__release()")
    assert_writes_settled
    assert_list_current
    assert_equal [ second.id, @block.id, third.id ], server_order
  end

  test "a page trashed under me says so and offers the way back" do
    open_page
    as(@dana, channel: :admin) { assert Trash::Move.call(@page.reload).ok? }

    assert_selector "#editor-notice [data-editing-missing]", wait: LIVE
    assert_selector "#editor-notice a[href='#{admin_pages_path}']", text: "Back to pages"
  end

  test "a refreshed card keeps the count on its notes marker" do
    as(@dana, channel: :admin) { assert Notes::Start.call(@block, body: "Check the numbers").ok? }
    open_page
    marker = "#notes-marker-ContentBlock-#{@block.id}"
    assert_selector "#{marker}[data-has-notes] [data-notes-count]", text: "1", visible: :all, wait: LIVE

    dana_saves(@block, "Prices from May")
    assert_selector "#{card(@block)} .ProseMirror", text: "Prices from May", wait: LIVE
    assert_selector "#{marker}[data-has-notes] [data-notes-count]", text: "1", visible: :all
  end

  test "live refresh uses no Turbo request: no visit, no frame load, no stream" do
    open_page
    page.execute_script(<<~JS)
      window.__turbo = 0
      for (const name of [ "turbo:before-fetch-request", "turbo:before-stream-render", "turbo:visit" ]) document.addEventListener(name, () => { window.__turbo += 1 })
    JS
    dana_saves(@block, "Prices from May")
    assert_selector "#{card(@block)} .ProseMirror", text: "Prices from May", wait: LIVE
    added = add_block(by: @dana)
    assert_list_current
    await_frames

    assert_equal 0, page.evaluate_script("window.__turbo")
  end
end
