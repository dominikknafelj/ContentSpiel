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
    # First: the script below can raise, and the browser is shared with the tests that follow.
    page.driver.browser.page.command("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "no-preference" } ])
    page.execute_script("try { window.localStorage.removeItem('cs-notes-open') } catch (error) {}")
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

  # Counts every request to the editing GETs (not the claims and releases, which are POSTs), passing each through. Installed
  # for the page already open (`count_requests`) or before the next load
  # (`count_requests_from_load`).
  COUNTER = <<~JS.freeze
    window.__seen = []
    const real = window.fetch
    window.fetch = function (input, init = {}) {
      const url = typeof input === "string" ? input : input.url
      // The GETs: a claim or a release (a POST to the same place) is the hold's, not a read.
      if (url.includes("/cs-studio/editing/") && String(init.method || "GET").toUpperCase() === "GET") window.__seen.push(url)
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

  # Holds the NEXT request of `method` whose URL matches `source` (a regexp's
  # text): the real request is made at once, so what it reads is what the
  # server holds NOW, and its answer reaches the page only at `release`
  # (`window.__arrived[name]` says the server has answered). Every other
  # request passes through untouched.
  def hold_next(name, method, source)
    page.execute_script(<<~JS, name, method, source)
      const [ name, method, source ] = arguments
      window.__release = window.__release || {}
      window.__arrived = window.__arrived || {}
      let spent = false
      const real = window.fetch
      window.fetch = function (input, init = {}) {
        const url = typeof input === "string" ? input : input.url
        const verb = String(init.method || input.method || "GET").toUpperCase()
        if (!spent && verb === method && new RegExp(source).test(url)) {
          spent = true
          const answer = real.apply(this, arguments)
          answer.then(() => { window.__arrived[name] = true })
          return new Promise((resolve) => { window.__release[name] = () => answer.then(resolve) })
        }
        return real.apply(this, arguments)
      }
    JS
  end

  def held?(name) = page.evaluate_script("Boolean(window.__release && window.__release[#{name.to_json}])")

  def release(name) = page.execute_script("window.__release[#{name.to_json}]()")

  LIST_GET = '/editing/page/\\d+/blocks(\\?.*)?$'.freeze
  BLOCK_GET = '/editing/page/\\d+/blocks/\\d+'.freeze

  def live_controller_js = "window.Stimulus.getControllerForElementAndIdentifier(document.getElementById('editing'), 'admin--editing--live')"

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

  # The mark's life as the SCRIPT timed it, read from the script's own timers
  # and never from a clock of the test's. A lower bound measured from outside
  # ("the mark stayed at least 890 ms") cannot hold: an observer in the page
  # hears of the mark only after the card's editor has been mounted, tens of
  # milliseconds after the script armed its timer on a slow machine, and CI
  # measured 843 and 870 ms for a wait of 900. So `setTimeout` is wrapped, and
  # only for the mark: a timer of exactly the notice's length (`NOTICE_MS`, a
  # number nothing else in the page waits for) and one armed from inside that
  # timer's own callback (the fade). Each records what the mark was when it was
  # armed, when it was due and after it ran: "shown", "leaving" or "gone".
  NOTICE_MS = 937

  def watch_mark
    page.execute_script(<<~JS, NOTICE_MS)
      const [ notice ] = arguments
      window.__mark = []
      const state = () => {
        const mark = document.querySelector("[data-editing-mark]")
        return !mark ? "gone" : (mark.classList.contains("admin-editing-mark--leaving") ? "leaving" : "shown")
      }
      const real = window.setTimeout
      let inside = false
      window.setTimeout = function (act, ms, ...rest) {
        if (typeof act !== "function" || !(ms === notice || inside)) return real.call(window, act, ms, ...rest)
        window.__mark.push([ "armed", ms, state() ])
        return real.call(window, () => {
          window.__mark.push([ "due", ms, state() ])
          const outer = inside
          inside = true
          try { act(...rest) } finally { inside = outer }
          window.__mark.push([ "ran", ms, state() ])
        }, ms)
      }
    JS
  end

  def mark_life = page.evaluate_script("window.__mark")

  test "the mark stays for the notice, then the fade starts, and the mark is gone" do
    open_page
    # Not the 6 seconds of the default: the region's value decides.
    set_value("notice", NOTICE_MS)
    watch_mark
    dana_saves(@block, "Prices from May")
    assert_selector "#{card(@block)} [data-editing-mark]", text: "Updated by Dana Weiss", wait: LIVE
    assert_no_selector "[data-editing-mark]", wait: LIVE

    # Armed for the notice's time with the mark in the document, still shown
    # when that time was up, fading from then for 200 ms, and gone after it.
    assert_equal [
      [ "armed", NOTICE_MS, "shown" ], [ "due", NOTICE_MS, "shown" ],
      [ "armed", 200, "leaving" ], [ "ran", NOTICE_MS, "leaving" ],
      [ "due", 200, "leaving" ], [ "ran", 200, "gone" ]
    ], mark_life
    # The fade is the stylesheet's: 200 ms, an opacity transition.
    duration = page.evaluate_script("(() => { const probe = document.createElement('span'); probe.className = 'admin-editing-mark'; document.body.append(probe); const value = getComputedStyle(probe).transitionDuration; probe.remove(); return value })()")
    assert_equal "0.2s", duration
  end

  test "with reduced motion the mark goes when its time is up, without fading" do
    page.driver.browser.page.command("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    open_page
    set_value("notice", NOTICE_MS)
    watch_mark
    dana_saves(@block, "Prices from May")
    assert_selector "#{card(@block)} [data-editing-mark]", wait: LIVE
    assert_no_selector "[data-editing-mark]", wait: LIVE

    # Shown until its time was up, then gone at once: no fade, and no second timer.
    assert_equal [ [ "armed", NOTICE_MS, "shown" ], [ "due", NOTICE_MS, "shown" ], [ "ran", NOTICE_MS, "gone" ] ], mark_life
  end

  test "my own save draws no mark and fetches nothing" do
    open_page
    count_requests
    type_in(@block, "My own text")
    assert_writes_settled
    await_frames

    assert_equal [], page.evaluate_script("window.__seen")
    assert_no_selector "[data-editing-mark]"

    # "Nothing" above is only as good as the cable was quick: a colleague's
    # save, which IS heard, follows, and its read is the only one ever made.
    dana_saves(@block, "Theirs")
    await_js("window.__seen.length > 0", wait: LIVE)
    assert_selector "#{card(@block)} .ProseMirror", text: "Theirs", wait: LIVE
    assert_equal 1, page.evaluate_script("window.__seen").size, "this tab also fetched its own save: #{page.evaluate_script("window.__seen").inspect}"
  end

  # Every write of an editor carries the tab header, or the server cannot say
  # whose echo it is (`Current.editing_tab`): a reorder, which is a hand-built
  # `fetch`, and a Turbo form, which gets it from `editing/requests`.
  test "my own reorder and my own Turbo form fetch and draw nothing" do
    second = add_block
    third = add_block
    open_page
    count_requests
    listen_merged

    find("#{card(second)} button[aria-label='Block actions']").click
    within(card(second)) { press "Move up" }
    assert_writes_settled
    assert_eventually(message: "the move was not saved") { server_order == [ second.id, @block.id, third.id ] }

    find("#{card(third)} button[aria-label='Block actions']").click
    within(card(third)) { press "Delete block…" }
    within("dialog[open]") { press "Delete block" }
    assert_no_selector card(third)
    assert_writes_settled
    await_frames

    assert_equal [], page.evaluate_script("window.__seen"), "this tab fetched what it had written itself"
    assert_equal [], page.evaluate_script("window.__merged"), "this tab drew what it had written itself"

    # As above: a colleague's save, which is heard, is the only read ever made.
    dana_saves(second, "Theirs")
    await_js("window.__merged.length > 0", wait: LIVE)
    assert_equal 1, page.evaluate_script("window.__seen").size, "this tab also fetched what it had written itself: #{page.evaluate_script("window.__seen").inspect}"
    assert_equal [ "block:#{second.id}" ], page.evaluate_script("window.__merged")
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
    # Nothing on a hidden page changes to wait on but what it owes.
    await_js("#{live_controller_js}.owed.has('blocks') && #{live_controller_js}.owed.has('record')", wait: LIVE)
    assert_equal [], page.evaluate_script("window.__seen")

    show_document
    assert_eventually(wait: LIVE, message: "the hidden tab never caught up") { blocks_requests.size == 1 && record_requests.size == 1 }
    assert_selector "#{card(@block)} .ProseMirror", text: "Second", wait: LIVE
    assert_list_current
    assert_includes list_order, added.id
    await_frames
    assert_equal 1, blocks_requests.size
    assert_equal 1, record_requests.size
    assert_equal [], requests(%r{/blocks/\d+}), "a block was fetched beside the list"
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

  test "a catch-up after a reconnect leaves a card that did not change as it is, with its menu open, and draws one that did" do
    second = add_block
    open_page
    find("#{card(@block)} button[aria-label='Block actions']").click
    assert_selector "#{card(@block)} [role=menu]"
    page.execute_script("window.__card = document.querySelector(#{card(@block).to_json}); window.__other = document.querySelector(#{card(second).to_json})")
    page.execute_script("import('@hotwired/turbo-rails').then((turbo) => turbo.cable.getConsumer()).then((consumer) => { window.__consumer = consumer })")
    await_js("Boolean(window.__consumer)")
    page.execute_script("window.__consumer.connection.close()")
    await_js("document.body.dataset.notesLive !== 'connected'", wait: LIVE)
    dana_saves(second, "While you were away")
    page.execute_script("window.__consumer.connection.open()")

    assert_selector "#{card(second)} .ProseMirror", text: "While you were away", wait: LIVE
    await_js("document.body.dataset.notesLive === 'connected'", wait: LIVE)
    assert_equal true, page.evaluate_script("window.__card === document.querySelector(#{card(@block).to_json})"), "a card that did not change was replaced by the catch-up"
    assert_selector "#{card(@block)} [role=menu]"
    assert_equal false, page.evaluate_script("window.__other === document.querySelector(#{card(second).to_json})")
  end

  test "a drop made while a colleague changed the list is refused as stale and the list is redrawn, and nothing was drawn during the drag" do
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

  test "a page trashed under me says so and offers the way back, and the part has answered" do
    open_page
    as(@dana, channel: :admin) { assert Trash::Move.call(@page.reload).ok? }

    assert_selector "#editor-notice [data-editing-missing]", wait: LIVE
    assert_selector "#editor-notice a[href='#{admin_pages_path}']", text: "Back to pages"
    assert_equal "answered", page.evaluate_script("document.getElementById('editing').dataset.livePart")
  end

  test "the missing bar is appended: a Changed elsewhere bar already in the notice area stays" do
    open_page
    page.execute_script("document.getElementById('editor-notice').innerHTML = '<div id=\\'changed-elsewhere\\' role=\\'alert\\'>Changed elsewhere</div>'")
    as(@dana, channel: :admin) { assert Trash::Move.call(@page.reload).ok? }

    assert_selector "#editor-notice [data-editing-missing]", wait: LIVE
    assert_selector "#editor-notice #changed-elsewhere"
  end

  test "a subscription that is rejected fetches the record once, and its 404 says the page is gone" do
    open_page
    page.execute_script("import('@hotwired/turbo-rails').then((turbo) => turbo.cable.getConsumer()).then((consumer) => { window.__consumer = consumer })")
    await_js("Boolean(window.__consumer)")
    page.execute_script("window.__consumer.connection.close()")
    await_js("document.body.dataset.notesLive !== 'connected'", wait: LIVE)
    # Trashed with nobody told: only the refused subscription can say so.
    as_unheard(@dana) { assert Trash::Move.call(@page.reload).ok? }
    page.execute_script("window.__consumer.connection.open()")

    assert_selector "#editor-notice [data-editing-missing]", wait: LIVE
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

  # --- one line of reads ---------------------------------------------------------

  test "a slow list answer and a newer block answer end with the newest content and the newest base on screen" do
    open_page
    hold_next("list", "GET", LIST_GET)
    added = add_block(by: @dana)
    await_js("window.__arrived && window.__arrived.list", wait: LIVE)
    # The list was READ before this save; a block answer for it follows the list's, never precedes it.
    dana_saves(@block, "Prices from May")
    # The save has been heard: its read waits for the list's answer (one line of reads) -- or, where reads do not wait, is already drawn.
    await_js("#{live_controller_js}.pending.has('block:#{@block.id}') || document.querySelector(#{card(@block).to_json}).textContent.includes('Prices from May')", wait: LIVE)
    await_frames
    release("list")

    assert_selector "#{card(@block)} .ProseMirror", text: "Prices from May", wait: LIVE
    assert_includes list_order, added.id
    type_in(@block, " and June")
    assert_writes_settled
    assert_no_selector "#changed-elsewhere"
    assert_eventually(message: "the block does not hold both texts") { ContentBlock.find(@block.id).body.to_json.then { |text| text.include?("Prices from May") && text.include?("and June") } }
  end

  test "a slow block answer and a newer list answer end with the newest content and the newest list" do
    open_page
    hold_next("block", "GET", BLOCK_GET)
    dana_saves(@block, "First")
    await_js("window.__arrived && window.__arrived.block", wait: LIVE)
    dana_saves(@block, "Second")
    added = add_block(by: @dana)
    await_js("#{live_controller_js}.pending.size > 0 || document.querySelector(#{card(@block).to_json}).textContent.includes('Second')", wait: LIVE)
    await_frames
    release("block")

    assert_selector "#{card(@block)} .ProseMirror", text: "Second", wait: LIVE
    assert_no_selector "#{card(@block)} .ProseMirror", text: "First"
    assert_list_current
    assert_includes list_order, added.id
    type_in(@block, " and mine")
    assert_writes_settled
    assert_no_selector "#changed-elsewhere"
  end

  # --- what is owed during a move is paid ----------------------------------------

  test "what a colleague saved during a drag is drawn after an accepted drop" do
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

    mouse = drag_pointer(from_x, from_y, (second_y + third_y) / 2)
    assert_selector "body > .admin-drag-fallback"
    dana_saves(third, "Saved during your drag")
    await_js("#{live_controller_js}.owed.has('block:#{third.id}')", wait: LIVE)
    await_frames
    assert_no_selector "#{card(third)} .ProseMirror", text: "Saved during your drag"
    await_drag_slot_after(second)
    mouse.up

    assert_writes_settled
    assert_selector "#{card(third)} .ProseMirror", text: "Saved during your drag", wait: LIVE
    assert_equal [ second.id, @block.id, third.id ], server_order
  end

  test "a keyboard pick-up that is put back says so: what was owed is drawn then, and not before" do
    open_page
    handle = "#{card(@block)} .admin-block-card__handle"
    find(handle).send_keys(:space)
    await_js("#{live_controller_js}.moving === true", wait: LIVE)
    added = add_block(by: @dana)
    await_js("#{live_controller_js}.owed.has('blocks')", wait: LIVE)
    await_frames
    assert_no_selector card(added)

    find(handle).send_keys(:escape)
    assert_selector card(added), wait: LIVE
    assert_equal false, page.evaluate_script("#{live_controller_js}.moving")
  end

  test "a pick-up made before an earlier move was answered keeps the list from being redrawn under it" do
    second = add_block
    third = add_block
    open_page
    hold_next("move", "PATCH", "/reorder")
    find("#{card(@block)} button[aria-label='Block actions']").click
    within(card(@block)) { press "Move down" }
    await_js("window.__release && window.__release.move", wait: LIVE)

    find("#{card(third)} .admin-block-card__handle").send_keys(:space)
    added = add_block(by: @dana)
    await_js("#{live_controller_js}.owed.has('blocks')", wait: LIVE)
    release("move")
    assert_writes_settled
    await_frames
    # The first move is answered; the pick-up is still in the person's hand.
    assert_equal true, page.evaluate_script("#{live_controller_js}.moving")
    assert_no_selector card(added)

    find("#{card(third)} .admin-block-card__handle").send_keys(:escape)
    assert_selector card(added), wait: LIVE
    assert_list_current
  end

  # --- a block someone else moved while I have unsent text in it -----------------

  test "a block moved into a section while I have unsent text stays, and takes its place once, after my save" do
    section = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "section", settings: { "layout" => "two" } }).record
    open_page
    type_unsent(@block, "My draft")
    count_requests
    listen_merged
    as(@dana, channel: :admin) do
      assert ContentBlocks::Reorder.call(@page.reload, [ @block.id ], section: section.id, column: 1, moved_from: { @block.id => { section_id: "", column: "" } }).ok?
    end
    await_js("window.__merged.length > 0", wait: LIVE)
    await_frames

    assert_selector "#content-blocks-list > #{card(@block)}"
    assert_selector "#{card(@block)} .ProseMirror", text: "My draft"
    assert_equal 1, blocks_requests.size
    # Unsaved still: the in-page check costs no request.
    sleep 1.3 # sleep: the moved-block check runs once a second; shows it asks for nothing while the text is unsaved
    assert_equal 1, blocks_requests.size

    page.execute_script(<<~JS)
      const form = document.querySelector(#{"#{card(@block)} form[data-controller~='admin--saving--autosave']".to_json})
      window.Stimulus.getControllerForElementAndIdentifier(form, "admin--saving--autosave").trigger()
    JS
    assert_no_selector "#content-blocks-list > #{card(@block)}", wait: LIVE
    assert_eventually(message: "the saved text was lost") { ContentBlock.find(@block.id).body.to_json.include?("My draft") }
    await_frames
    assert_equal 2, blocks_requests.size, "the list was fetched #{blocks_requests.size} times, not once more"
  end

  # --- what is open is not taken from under the person ---------------------------

  test "a card with the rich-text dialog open for it is kept while it is open, and refreshed when it closes" do
    open_page
    page.execute_script("window.__card = document.querySelector(#{card(@block).to_json})")
    listen_merged
    page.execute_script(<<~JS)
      const opener = document.querySelector(#{"#{card(@block)} [data-controller~='admin--rich-text--editor']".to_json})
      window.dispatchEvent(new CustomEvent("rich-text-dialog:open", { detail: { kind: "youtube", opener } }))
    JS
    assert_selector "dialog#rich-text-youtube-dialog[open]"

    dana_saves(@block, "Theirs")
    await_js("window.__merged.length > 0", wait: LIVE)
    await_frames
    assert_equal true, page.evaluate_script("window.__card === document.querySelector(#{card(@block).to_json})"), "the card was replaced under an open dialog"

    page.execute_script("document.getElementById('rich-text-youtube-dialog').close()")
    assert_selector "#{card(@block)} .ProseMirror", text: "Theirs", wait: LIVE
    assert_equal false, page.evaluate_script("window.__card === document.querySelector(#{card(@block).to_json})")
  end

  test "a card whose menu is open is kept while it is open, and refreshed when it closes" do
    open_page
    find("#{card(@block)} button[aria-label='Block actions']").click
    assert_selector "#{card(@block)} [role=menu]"
    page.execute_script("window.__card = document.querySelector(#{card(@block).to_json})")
    listen_merged

    dana_saves(@block, "Theirs")
    await_js("window.__merged.length > 0", wait: LIVE)
    await_frames
    assert_equal true, page.evaluate_script("window.__card === document.querySelector(#{card(@block).to_json})"), "the card was replaced under its open menu"
    assert_selector "#{card(@block)} [role=menu]"

    find("#{card(@block)} button[aria-label='Block actions']").click
    assert_selector "#{card(@block)} .ProseMirror", text: "Theirs", wait: LIVE
  end

  # --- a read that does not come back --------------------------------------------

  # Shortens the script's own waits on the next load, before its controller
  # connects, and fails or hangs the first read of `source`.
  def with_unreliable_reads(mode, source)
    script = <<~JS
      new MutationObserver((_, observer) => {
        const region = document.getElementById("editing")
        if (!region) return
        region.setAttribute("data-admin--editing--live-timeout-value", "500")
        region.setAttribute("data-admin--editing--live-retry-value", "200")
        observer.disconnect()
      }).observe(document, { childList: true, subtree: true })
      window.__seen = []
      let spent = false
      const real = window.fetch
      window.fetch = function (input, init = {}) {
        const url = typeof input === "string" ? input : input.url
        if (url.includes("/cs-studio/editing/")) window.__seen.push(url)
        if (!spent && new RegExp(#{source.to_json}).test(url)) {
          spent = true
          if (#{mode.to_json} === "fail") return Promise.reject(new TypeError("offline"))
          return new Promise((_, reject) => init.signal.addEventListener("abort", () => reject(new DOMException("timed out", "TimeoutError"))))
        }
        return real.apply(this, arguments)
      }
    JS
    id = page.driver.browser.page.command("Page.addScriptToEvaluateOnNewDocument", source: script)["identifier"]
    yield
  ensure
    page.driver.browser.page.command("Page.removeScriptToEvaluateOnNewDocument", identifier: id) if id
  end

  test "a read that fails is asked again, and the part has answered meanwhile" do
    with_unreliable_reads("fail", "/editing/page/\\d+/record") do
      open_page
      assert_eventually(wait: LIVE, message: "the failed read was never asked again") { record_requests.size >= 2 }
    end
  end

  test "a read that never comes back times out, the part answers, and it is asked again" do
    with_unreliable_reads("hang", "/editing/page/\\d+/blocks(\\?.*)?$") do
      open_page
      assert_eventually(wait: LIVE, message: "the timed out read was never asked again") { blocks_requests.size >= 2 }
    end
  end

  # --- a block kept for an open dialog or menu ----------------------------------

  def open_rich_text_dialog(kind, block = @block)
    page.execute_script(<<~JS, kind)
      const opener = document.querySelector(#{"#{card(block)} [data-controller~='admin--rich-text--editor']".to_json})
      window.dispatchEvent(new CustomEvent("rich-text-dialog:open", { detail: { kind: arguments[0], opener } }))
    JS
  end

  test "a card kept for one dialog is refreshed when the LAST of several dialogs on it closes" do
    open_page
    page.execute_script("window.__card = document.querySelector(#{card(@block).to_json})")
    listen_merged
    open_rich_text_dialog("youtube")
    assert_selector "dialog#rich-text-youtube-dialog[open]"
    # The picker closes and the next dialog opens in the same breath (the
    # alt-text dialog after the media picker): opened from a `close` listener
    # that runs after the script's own.
    page.execute_script(<<~JS)
      const first = document.getElementById("rich-text-youtube-dialog")
      first.addEventListener("close", () => {
        const opener = document.querySelector(#{"#{card(@block)} [data-controller~='admin--rich-text--editor']".to_json})
        window.dispatchEvent(new CustomEvent("rich-text-dialog:open", { detail: { kind: "page", opener } }))
      }, { once: true })
    JS
    dana_saves(@block, "Theirs")
    await_js("window.__merged.length > 0", wait: LIVE)
    page.execute_script("document.getElementById('rich-text-youtube-dialog').close()")
    assert_selector "dialog#rich-text-page-dialog[open]"
    await_frames
    assert_equal true, page.evaluate_script("window.__card === document.querySelector(#{card(@block).to_json})"), "the card was replaced between the two dialogs"

    page.execute_script("document.getElementById('rich-text-page-dialog').close()")
    assert_selector "#{card(@block)} .ProseMirror", text: "Theirs", wait: LIVE
  end

  test "a tile whose menu is open is kept while it is open, and block and tile are refreshed when it closes" do
    section = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "section", settings: { "layout" => "two" } }).record
    inside = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text", section_id: section.id, section_column: 1 }).record
    open_page
    tile = "#content-blocks-list ##{ActionView::RecordIdentifier.dom_id(inside)}.admin-block-tile"
    find("#{tile} button[aria-label='Block actions']").click
    assert_selector "#{tile} [role=menu]"
    page.execute_script("window.__tile = document.querySelector(#{tile.to_json}); window.__panel = document.getElementById('block-#{inside.id}-panel')")
    listen_merged

    dana_saves(inside, "Theirs")
    await_js("window.__merged.length > 0", wait: LIVE)
    await_frames
    assert_equal true, page.evaluate_script("window.__tile === document.querySelector(#{tile.to_json})"), "the tile was replaced under its open menu"
    assert_selector "#{tile} [role=menu]"

    find("#{tile} button[aria-label='Block actions']").click
    assert_eventually(wait: LIVE, message: "the block was not refreshed when the menu closed") do
      page.evaluate_script("window.__panel !== document.getElementById('block-#{inside.id}-panel')")
    end
    assert_selector "#block-#{inside.id}-panel .ProseMirror", text: "Theirs", visible: :all, wait: LIVE
  end

  # --- one line: an answer on the wire is drawn ----------------------------------

  test "two asks for one block with the first answer slow: both are drawn, in order, the newest last" do
    open_page
    page.execute_script(<<~JS)
      window.__texts = []
      document.getElementById("editing").addEventListener("admin--editing--live:merged", (event) => {
        if (event.detail.part.startsWith("block:")) window.__texts.push(event.detail.replaced.map((unit) => unit.outerHTML).join(""))
      })
    JS
    hold_next("slow", "GET", BLOCK_GET)
    dana_saves(@block, "First")
    await_js("window.__arrived && window.__arrived.slow", wait: LIVE)
    dana_saves(@block, "Second")
    await_js("#{live_controller_js}.pending.has('block:#{@block.id}')", wait: LIVE)
    release("slow")

    assert_eventually(wait: LIVE, message: -> { "texts drawn: #{page.evaluate_script('window.__texts').inspect}" }) { page.evaluate_script("window.__texts").size == 2 }
    texts = page.evaluate_script("window.__texts")
    assert_includes texts.first, "First"
    assert_includes texts.last, "Second"
  end

  # --- the mark survives being folded into a list ask ----------------------------

  test "a block's mark is not lost when its ask is folded into a list ask" do
    second = add_block
    open_page
    hold_next("slow", "GET", BLOCK_GET)
    dana_saves(@block, "First")
    await_js("window.__arrived && window.__arrived.slow", wait: LIVE)
    add_block(by: @dana)
    await_js("#{live_controller_js}.pending.has('blocks')", wait: LIVE)
    dana_saves(second, "Theirs")
    await_js("!#{live_controller_js}.pending.has('block:#{second.id}')", wait: LIVE)
    release("slow")

    assert_selector "#{card(second)} .ProseMirror", text: "Theirs", wait: LIVE
    assert_selector "#{card(second)} [data-editing-mark]", text: "Updated by Dana Weiss", wait: LIVE
  end

  # --- the two exits of `moving` that are not Escape -----------------------------

  def blocks_controller_js = "window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller~=\\'admin--editor--blocks\\']'), 'admin--editor--blocks')"

  test "putBack lets go of a keyboard pick-up, and the list that was owed is drawn" do
    open_page
    handle = "#{card(@block)} .admin-block-card__handle"
    find(handle).send_keys(:space)
    await_js("#{live_controller_js}.moving === true", wait: LIVE)
    added = add_block(by: @dana)
    await_js("#{live_controller_js}.owed.has('blocks')", wait: LIVE)
    assert_no_selector card(added)

    # What a refused or failed move calls (`putBack`), not Escape (`cancel`).
    page.execute_script("#{blocks_controller_js}.putBack()")
    assert_selector card(added), wait: LIVE
    assert_equal false, page.evaluate_script("#{live_controller_js}.moving")
  end

  # A drag cannot be held open across a Capybara step, and SortableJS calls no
  # `onEnd` for `destroy()`: the controller's own path (`laneTargetDisconnected`)
  # is reached by taking the lane out of the document while the controller
  # holds a drag in that lane (`dragging`, and the instance Sortable calls active).
  test "a lane destroyed under a drag lets go of it, and the list that was owed is drawn" do
    section = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "section", settings: { "layout" => "two" } }).record
    open_page
    page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      import("sortablejs").then(({ default: Sortable }) => {
        const lane = document.getElementById("section-#{section.id}-lane-1")
        const controller = #{blocks_controller_js}
        controller.dragging = true
        Sortable.active = { el: lane }
        controller.sayMoving()
        done(true)
      })
    JS
    await_js("#{live_controller_js}.moving === true", wait: LIVE)
    added = add_block(by: @dana)
    await_js("#{live_controller_js}.owed.has('blocks')", wait: LIVE)

    page.execute_script("document.getElementById('section-#{section.id}-lane-1').remove()")
    assert_selector card(added), wait: LIVE
    assert_equal false, page.evaluate_script("#{live_controller_js}.moving")
  end
end
