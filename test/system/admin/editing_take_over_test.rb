require "application_system_test_case"

# Taking over, in the browser (live-editing spec §4.4,
# `controllers/admin/editing/hold_controller.js`): "Take over" asks the
# holder's tab, which locks its fields for the subject, sends what it has and
# lets go; a tab that does not answer is passed over after the pass-over time.
# Two or three people are two or three Capybara sessions (`using_session`).
# Nobody waits for the real five seconds: the script's wait is shortened
# through the region's value (`quick_pass_over`) and the server's clock is
# moved on the row (`due`), as the reservation tests move clocks. A tab that
# does not hear that the block was taken is `stop_hearing_taken`, with its
# hand-over request held in a `fetch` stub that takes only its own request; a
# holder that is gone is a row made through the model with a tab no browser
# has. (A tab that is truly asleep, with text that is refused when it wakes,
# is the lapsed-save test of `editing_holds_test.rb`.)
class Admin::EditingTakeOverSystemTest < ApplicationSystemTestCase
  include TestTypes

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
  end

  def quick_pass_over(ms = 300) = region_set("pass-over", ms)

  # The asking tab's request is old enough to be passed over (the server's clock
  # is the row's: a request is due PASS_OVER after it was made).
  def due(subject = @block)
    Editing::Reservation.of(subject).update_all(requested_at: 6.seconds.ago) # version: none (a system test moves a request's clock)
  end

  def waiting_status(block = @block) = "#{strip(block)} [data-editing-take-over-status]"

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

  def add_block(owner: @page, **attributes)
    ContentBlocks::Save.call(ContentBlock.new(owner: owner), attributes: { block_type: "rich_text" }.merge(attributes)).record
  end

  def card(block) = "#content_block_#{block.id}"

  def panel(block) = "#block-#{block.id}-panel"

  def type_in(block, text, within: card(block))
    find("#{within} .ProseMirror").click
    find("#{within} .ProseMirror").send_keys(text)
  end

  def autosave_form(within) = "#{within} form[data-controller~='admin--saving--autosave']"

  def raise_debounce(within, ms = 600000)
    page.execute_script("document.querySelector(#{autosave_form(within).to_json}).setAttribute('data-admin--saving--autosave-debounce-value', #{ms})")
  end

  def expire(subject = @block)
    Editing::Reservation.of(subject).update_all(changed_at: 3.minutes.ago) # version: none (a system test moves a reservation's clock)
  end

  def held_by(user, subject = @block) = Editing::Reservation.holder_of(subject)&.user_id == user.id

  def body_of(block) = block.reload.body_document(locale: "en").to_json

  def body_text_of(block) = block.reload.body_document(locale: "en").to_json.scan(/"text":"([^"]*)"/).flatten.join

  def region_set(name, value) = page.execute_script("document.getElementById('editing').setAttribute('data-admin--editing--hold-#{name}-value', #{value.to_json})")

  def taken_over_events = Audit::Event.where(action: %w[block.taken_over page.taken_over post.taken_over])

  # A holder that is not a browser at all: its row stands, its tab answers nothing.
  def held_by_nobody_listening(subject = @block, record: @page, user: @dana)
    Editing::Reservation.claim(subject: subject, record: record, user: user, tab: "tab-dddddddd")
  end

  # The mutating requests this page sent, in order, as "VERB /path".
  RECORD = <<~JS.freeze
    window.__sent = window.__sent || []
    if (!window.__recording) {
      window.__recording = true
      const real = window.fetch
      window.fetch = function (input, init = {}) {
        const url = typeof input === "string" ? input : input.url
        const verb = String(init.method || "GET").toUpperCase()
        if (verb !== "GET") window.__sent.push(verb + " " + new URL(url, window.location.href).pathname)
        return real.apply(this, arguments)
      }
    }
  JS

  def record_requests = page.execute_script(RECORD)

  def sent = page.evaluate_script("window.__sent")

  def take_over_requests = sent.grep(%r{/editing/\w+/\d+/take_over\z})

  def hand_over_requests = sent.grep(%r{/editing/\w+/\d+/hand_over\z})

  # Holds the NEXT request of `verb` whose URL matches `source` BEFORE it is
  # sent: it reaches the server only at `send_delayed`.
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

  # Answers the NEXT request of `verb` matching `source` with `status` and `body`,
  # without sending it; every other request goes through.
  def answer_next(verb, source, status, body = "", type: nil)
    page.execute_script(<<~JS, verb, source, status, body, type)
      const [ verb, source, status, body, type ] = arguments
      let spent = false
      const real = window.fetch
      window.fetch = function (input, init = {}) {
        const url = typeof input === "string" ? input : input.url
        const method = String(init.method || "GET").toUpperCase()
        if (!spent && method === verb && new RegExp(source).test(url)) {
          spent = true
          return Promise.resolve(new Response(body, { status, headers: type ? { "Content-Type": type } : {} }))
        }
        return real.apply(this, arguments)
      }
    JS
  end

  # This tab hears no news that the block was taken -- it still hears when it
  # is asked to hand over. `hear_taken` puts the hearing back.
  def stop_hearing_taken
    page.execute_script(<<~JS)
      const live = window.Stimulus.getControllerForElementAndIdentifier(document.getElementById('editing'), 'admin--editing--live')
      const heard = Object.getPrototypeOf(live).heard
      live.heard = (signal) => { if (signal.kind === "holder" && signal.reason === "requested") heard.call(live, signal) }
    JS
  end

  def hear_taken
    page.execute_script(<<~JS)
      const live = window.Stimulus.getControllerForElementAndIdentifier(document.getElementById('editing'), 'admin--editing--live')
      delete live.heard
    JS
  end

  # This holder never hands over (its script is told not to): the request stands
  # until it is passed over, withdrawn, or the holder lets go.
  def refuse_to_hand_over
    page.execute_script("window.Stimulus.getControllerForElementAndIdentifier(document.getElementById('editing'), 'admin--editing--hold').handOver = () => {}")
  end

  # The NEXT request of `verb` matching `source` fails as a dead network does.
  def fail_next(verb, source)
    page.execute_script(<<~JS, verb, source)
      const [ verb, source ] = arguments
      let spent = false
      const real = window.fetch
      window.fetch = function (input, init = {}) {
        const url = typeof input === "string" ? input : input.url
        if (!spent && String(init.method || "GET").toUpperCase() === verb && new RegExp(source).test(url)) {
          spent = true
          return Promise.reject(new TypeError("offline"))
        }
        return real.apply(this, arguments)
      }
    JS
  end

  # A person typing a letter every `every` ms into the block's field, for as
  # long as the page lives (what the field refuses, it refuses).
  def type_continuously(block, every: 30)
    page.execute_script(<<~JS, "#{card(block)} .ProseMirror", every)
      const [ selector, every ] = arguments
      const editor = document.querySelector(selector)
      window.__typing = setInterval(() => {
        editor.focus()
        const range = document.createRange()
        range.selectNodeContents(editor)
        range.collapse(false)
        getSelection().removeAllRanges()
        getSelection().addRange(range)
        document.execCommand("insertText", false, "x")
      }, every)
    JS
  end

  def stop_typing = page.execute_script("clearInterval(window.__typing)")

  # Records every text put into the polite regions, to hear a transfer said once.
  def watch_announcements
    page.execute_script(<<~JS)
      window.__said = []
      new MutationObserver((records) => {
        records.forEach((record) => record.addedNodes.forEach((node) => {
          if (node.nodeType === 3 && record.target.closest && record.target.closest("[data-editing-announcer]")) window.__said.push(node.textContent)
        }))
      }).observe(document.body, { childList: true, subtree: true })
    JS
  end

  def said = page.evaluate_script("window.__said")

  def active_in?(selector) = page.evaluate_script("Boolean(document.activeElement && document.activeElement.closest(#{selector.to_json}))")

  def strip(block = @block) = "#{card(block)} [data-editing-kind=held]"

  # --- the brief's -----------------------------------------------------------

  test "taking over a block someone is typing in: their unsaved text arrives first, the block is mine with it, and theirs says who took it" do
    open_page
    join(:dana, @dana) do
      type_in(@block, "Saved text. ")
      assert_writes_settled
      raise_debounce(card(@block))
      type_in(@block, "Not yet saved.")
    end
    assert_selector "#{card(@block)} [data-editing-kind=held]", text: "Dana Weiss is editing this block", wait: LIVE

    within(card(@block)) { press "Take over" }

    assert_selector "#{card(@block)} form[data-controller~='admin--saving--autosave'] .ProseMirror", text: "Saved text. Not yet saved.", wait: LIVE
    assert_no_selector "#{card(@block)} [data-editing-kind=held]"
    assert_equal @me.id, Editing::Reservation.holder_of(@block).user_id
    event = Audit::Event.where(action: "block.taken_over").sole
    assert_equal({ "from_user_id" => @dana.id, "to_user_id" => @me.id, "answered" => true }, event.metadata)
    assert_equal 1, taken_over_events.count

    using_session(:dana) do
      assert_selector "#{card(@block)} [data-editing-strip-text]", text: "Taken over by Olga Braun", wait: LIVE
      assert_selector "#{card(@block)} [data-editing-announcer]", text: "Olga Braun took over this block", visible: :all
      assert_selector "#{card(@block)} .ProseMirror[contenteditable=false]", text: "Saved text. Not yet saved."
      assert_no_selector "#toasts [role=status], #toasts [role=alert]"
      assert_no_selector "[data-editing-kind=lost], [data-editing-kind=deleted]"
    end

    # The audit log says who gave it up.
    visit admin_audit_events_path
    assert_text "handed over editing"
  end

  test "the notice becomes the ordinary strip after its time" do
    open_page
    join(:dana, @dana) do
      type_in(@block, "Mine for now")
      assert_writes_settled
      region_set("notice", 300)
    end
    assert_selector strip, text: "Dana Weiss is editing this block", wait: LIVE
    within(card(@block)) { press "Take over" }

    using_session(:dana) do
      assert_selector "#{strip} [data-editing-strip-text]", text: "Olga Braun is editing this block", wait: LIVE
      assert_no_selector "#{card(@block)} [data-editing-strip-text]", text: "Taken over", wait: LIVE
    end
  end

  test "from a tab that does not answer: after the pass-over time the block is mine on what was saved" do
    held_by_nobody_listening
    open_page
    quick_pass_over
    record_requests
    assert_selector strip, text: "Dana Weiss is editing this block"

    within(card(@block)) { press "Take over" }
    assert_selector waiting_status, text: "Asking to take over…", wait: LIVE
    due

    assert_selector "#{card(@block)} form[data-controller~='admin--saving--autosave'] .ProseMirror[contenteditable=true]", wait: LIVE
    assert_no_selector strip
    assert held_by(@me)
    assert_operator take_over_requests.size, :>=, 2
    assert_equal 0, hand_over_requests.size
    event = Audit::Event.where(action: "block.taken_over").sole
    assert_equal({ "from_user_id" => @dana.id, "to_user_id" => @me.id, "answered" => false }, event.metadata)
    assert_equal 1, taken_over_events.count
    visit admin_audit_events_path
    assert_text "took over editing"
  end

  test "a tab that does not hear it was passed over, and whose hand-over came too late, keeps what it types after, read-only, with the notice" do
    open_page
    quick_pass_over
    join(:dana, @dana) do
      type_in(@block, "Saved. ")
      assert_writes_settled
      raise_debounce(card(@block))
      type_in(@block, "Typed while asleep. ")
      stop_hearing_taken
      delay_next("POST", "/hand_over")
    end
    assert_selector strip, text: "Dana Weiss is editing this block", wait: LIVE

    within(card(@block)) { press "Take over" }
    assert_selector waiting_status, text: "Asking to take over…", wait: LIVE
    due
    assert_selector "#{card(@block)} form[data-controller~='admin--saving--autosave'] .ProseMirror[contenteditable=true]", wait: LIVE
    assert_equal 1, taken_over_events.count

    using_session(:dana) do
      await_delayed
      send_delayed
      hear_taken
      # The hand-over was answered `nothing`: the lock comes off, and typing works again.
      assert_selector "#{card(@block)} .ProseMirror[contenteditable=true]", wait: LIVE
      raise_debounce(card(@block), 50)
      find("#{card(@block)} .ProseMirror").send_keys("Late.")
      assert_selector "#{card(@block)} [data-editing-kind=lost] [role=alert]", text: "Olga Braun is editing this block. Your changes weren't saved.", wait: LIVE
      assert_selector "#{card(@block)} .ProseMirror[contenteditable=false]", text: "Late."
      assert_selector "#{card(@block)} .ProseMirror", text: "Saved. Typed while asleep."
    end
    assert_equal 1, taken_over_events.count
    assert_includes body_of(@block), "Typed while asleep."
    refute_includes body_of(@block), "Late."
  end

  test "a tab that does not hear it was passed over, with nothing unsaved, shows the block as held by me once it reads" do
    open_page
    quick_pass_over
    join(:dana, @dana) do
      type_in(@block, "All saved. ")
      assert_writes_settled
      stop_hearing_taken
      delay_next("POST", "/hand_over")
    end
    assert_selector strip, wait: LIVE
    within(card(@block)) { press "Take over" }
    assert_selector waiting_status, text: "Asking to take over…", wait: LIVE
    due
    assert_selector "#{card(@block)} .ProseMirror[contenteditable=true]", wait: LIVE

    using_session(:dana) do
      await_delayed
      send_delayed
      hear_taken
      page.execute_script("document.getElementById('editing').dispatchEvent(new CustomEvent('admin--editing--hold:refresh', { detail: { subject: 'block-#{@block.id}' } }))")
      assert_selector "#{card(@block)} [data-editing-kind=held]", text: "Olga Braun is editing this block", wait: LIVE
      assert_selector "#{card(@block)} .ProseMirror[contenteditable=false]", text: "All saved."
      assert_no_selector "#{card(@block)} [data-editing-kind=lost]"
    end
    assert_equal 1, taken_over_events.count
  end

  test "taking over from my own other tab" do
    using_session(:other) do
      sign_in_via_form(@me)
      visit "/cs-studio/pages/#{@page.id}"
      await_notes_live
      type_in(@block, "From the other tab. ")
      assert_writes_settled
      raise_debounce(card(@block))
      type_in(@block, "Unsent.")
    end
    open_page
    assert_selector strip, text: "You're editing this in another tab", wait: LIVE

    within(card(@block)) { press "Take over" }

    assert_selector "#{card(@block)} form[data-controller~='admin--saving--autosave'] .ProseMirror", text: "From the other tab. Unsent.", wait: LIVE
    event = taken_over_events.sole
    assert_equal({ "from_user_id" => @me.id, "to_user_id" => @me.id, "answered" => true }, event.metadata)
    using_session(:other) do
      assert_selector "#{card(@block)} [data-editing-strip-text]", text: "Taken over by Olga Braun", wait: LIVE
      assert_selector "#{card(@block)} .ProseMirror[contenteditable=false]"
    end
  end

  test "Dana takes the block back" do
    open_page
    join(:dana, @dana) do
      type_in(@block, "Dana first. ")
      assert_writes_settled
    end
    assert_selector strip, wait: LIVE
    within(card(@block)) { press "Take over" }
    assert_selector "#{card(@block)} .ProseMirror[contenteditable=true]", text: "Dana first.", wait: LIVE
    type_in(@block, "Then Olga. ")
    assert_writes_settled

    using_session(:dana) do
      assert_selector "#{strip}", text: "Olga Braun is editing this block", wait: LIVE
      assert_selector "#{card(@block)} .ProseMirror", text: "Dana first. Then Olga.", wait: LIVE
      within(card(@block)) { press "Take over" }
      assert_selector "#{card(@block)} form[data-controller~='admin--saving--autosave'] .ProseMirror[contenteditable=true]", text: "Dana first. Then Olga.", wait: LIVE
      assert_no_selector strip
    end
    assert_selector "#{card(@block)} .ProseMirror[contenteditable=false]", wait: LIVE
    assert_selector strip, text: "Dana Weiss is editing this block", wait: LIVE
    assert_equal 2, taken_over_events.count
    assert_equal [ true, true ], taken_over_events.order(:id).map { |event| event.metadata["answered"] }
  end

  test "the card's menu has Take over and it does the same" do
    open_page
    join(:dana, @dana) do
      type_in(@block, "Dana's text")
      assert_writes_settled
    end
    assert_selector strip, wait: LIVE
    find("#{card(@block)} button[aria-label='Block actions']").click
    find("#{card(@block)} [data-admin--ui--menu-target~='panel'] button", text: "Take over").click

    assert_selector "#{card(@block)} form[data-controller~='admin--saving--autosave'] .ProseMirror[contenteditable=true]", text: "Dana's text", wait: LIVE
    assert_equal 1, taken_over_events.count
  end

  test "a post is taken over from the header's notice area" do
    post = create_post(title: "Hello", published: false)
    path = "/cs-studio/posts/#{post.id}"
    open_page(path)
    join(:dana, @dana, path: path) do
      find("input[name='post[title]']").fill_in(with: "Hello again")
      assert_writes_settled
    end
    assert_selector "#editor-notice [data-editing-kind=held]", text: "Dana Weiss is editing this post", wait: LIVE

    within("#editor-notice") { press "Take over" }

    assert_selector "#post-form[data-controller~='admin--saving--autosave'] input[name='post[title]']:not([readonly])", wait: LIVE
    assert_equal "Hello again", find("input[name='post[title]']").value
    assert_no_selector "#editor-notice [data-editing-kind=held]"
    assert_equal 1, Audit::Event.where(action: "post.taken_over").count
    using_session(:dana) do
      assert_selector "#editor-notice [data-editing-strip-text]", text: "Taken over by Olga Braun", wait: LIVE
      assert_selector "[data-editing-announcer]", text: "Olga Braun took over this post", visible: :all
      assert_selector "#post-form input[name='post[title]'][readonly]"
    end
  end

  test "the settings form is taken over from the strip at the top of its panel" do
    open_page
    join(:dana, @dana) do
      find("#page-title").fill_in(with: "Pricing 2")
      assert_writes_settled
    end
    assert_selector "#page-hold [data-editing-kind=held]", text: "Dana Weiss is editing the page settings", wait: LIVE

    within("#page-hold") { press "Take over" }

    assert_selector "#page-settings form[data-controller~='admin--saving--autosave'] #page-title:not([readonly])", wait: LIVE
    assert_equal "Pricing 2", find("#page-title").value
    assert_equal 1, Audit::Event.where(action: "page.taken_over").count
    using_session(:dana) do
      assert_selector "#page-hold [data-editing-strip-text]", text: "Taken over by Olga Braun", wait: LIVE
      assert_selector "#page-title[readonly]"
    end
  end

  test "an expired hold is simply mine at the press: no waiting, no event" do
    open_page
    held_by_nobody_listening
    # The page was drawn without the strip; draw it with the strip by a catch-up.
    visit "/cs-studio/pages/#{@page.id}"
    await_notes_live
    assert_selector strip
    expire
    record_requests

    within(card(@block)) { press "Take over" }

    assert_selector "#{card(@block)} form[data-controller~='admin--saving--autosave'] .ProseMirror[contenteditable=true]", wait: LIVE
    assert_no_selector strip
    assert_no_selector "[data-editing-take-over-status]:not(:empty)"
    assert_equal 0, taken_over_events.count
    assert_equal 1, take_over_requests.size
    assert held_by(@me)
  end

  test "a take-over raises no leave prompt and moves no base" do
    open_page
    join(:dana, @dana) do
      type_in(@block, "Dana's words. ")
      assert_writes_settled
    end
    assert_selector strip, wait: LIVE
    within(card(@block)) { press "Take over" }
    assert_selector "#{card(@block)} form[data-controller~='admin--saving--autosave'] .ProseMirror[contenteditable=true]", text: "Dana's words.", wait: LIVE

    base = page.evaluate_script("document.getElementById('block-#{@block.id}-base-updated-at').value")
    assert_equal @block.reload.updated_at.iso8601(6), base
    assert_equal false, page.evaluate_script("(() => { const event = new Event('beforeunload', { cancelable: true }); window.dispatchEvent(event); return event.defaultPrevented })()")
    type_in(@block, "And Olga's.")
    assert_writes_settled
    assert_includes body_of(@block), "And Olga's."
    assert_includes body_of(@block), "Dana's words."
  end

  test "a reader has no Take over" do
    open_page
    type_in(@block, "Writers")
    assert_writes_settled
    join(:reader, users(:reader)) do
      assert_selector strip, text: "Olga Braun is editing this block", wait: LIVE
      assert_no_selector "#{strip} button", text: "Take over"
      assert_no_selector "#{card(@block)} button", text: "Take over", visible: :all
    end
  end

  # --- the flows -------------------------------------------------------------

  test "someone else is already taking this over: it says so, once, and sends one request" do
    reader = users(:reader)
    held_by_nobody_listening
    Editing::Reservation.request(subject: @block, by: reader, tab: "tab-cccccccc")
    open_page
    record_requests

    within(card(@block)) { press "Take over" }

    assert_selector "#{strip} [data-editing-take-over-status]", text: "Someone else is already taking this over", wait: LIVE
    assert_no_selector "#{strip} button[disabled]"
    assert_equal 1, take_over_requests.size
    assert_equal 0, taken_over_events.count
    assert held_by(@dana)
  end

  test "a take-over that is refused says it did not work, freezes nothing, and the button is ready again" do
    held_by_nobody_listening
    open_page
    record_requests
    answer_next("POST", "/take_over", 403, "{}")

    within(card(@block)) { press "Take over" }

    assert_selector "#{strip} [data-editing-take-over-status]", text: "Couldn't take over. Try again.", wait: LIVE
    assert_no_selector "#{strip} button[disabled]"
    assert_selector "#{card(@block)} .ProseMirror[contenteditable=false]"
    assert_no_selector "#{card(@block)} [data-editing-kind=lost]"
    assert_equal 0, taken_over_events.count
    assert held_by(@dana)
  end

  test "a double click on Take over sends one request" do
    held_by_nobody_listening
    open_page
    quick_pass_over(2500)
    record_requests
    page.execute_script("const button = document.querySelector(#{"#{strip} button".to_json}); button.click(); button.click(); button.click()")

    assert_selector waiting_status, text: "Asking to take over…", wait: LIVE
    assert_equal 1, take_over_requests.size
    due
    assert_selector "#{card(@block)} form[data-controller~='admin--saving--autosave'] .ProseMirror[contenteditable=true]", wait: LIVE
    assert_equal 1, taken_over_events.count
  end

  test "the holder cannot hand over: nothing is handed over while text cannot be saved, the pass-over happens, and the holder's text is kept, frozen with the notice" do
    open_page
    quick_pass_over
    join(:dana, @dana) do
      region_set("pass-over", 1000)
      type_in(@block, "Saved. ")
      assert_writes_settled
      # From now on this tab's saves fail.
      page.execute_script(<<~JS)
        const real = window.fetch
        window.fetch = function (input, init = {}) {
          if (String(init.method || "GET").toUpperCase() === "PATCH") return Promise.reject(new TypeError("offline"))
          return real.apply(this, arguments)
        }
      JS
      record_requests
      type_in(@block, "Cannot be saved.")
    end
    assert_selector strip, wait: LIVE
    within(card(@block)) { press "Take over" }
    assert_selector waiting_status, text: "Asking to take over…", wait: LIVE
    due

    assert_selector "#{card(@block)} form[data-controller~='admin--saving--autosave'] .ProseMirror[contenteditable=true]", wait: 20
    assert_includes body_of(@block), "Saved."
    refute_includes body_of(@block), "Cannot be saved."
    event = taken_over_events.sole
    assert_equal false, event.metadata["answered"]

    using_session(:dana) do
      assert_equal [], hand_over_requests
      assert_selector "#{card(@block)} [data-editing-kind=lost] [role=alert]", text: "Olga Braun is editing this block. Your changes weren't saved.", wait: 20
      assert_selector "#{card(@block)} .ProseMirror[contenteditable=false]", text: "Cannot be saved."
    end
  end

  test "a holder who is typing hands over: the lock stops the typing, everything typed is in the block I get, and nothing says it was lost" do
    open_page
    join(:dana, @dana) do
      type_in(@block, "Start. ")
      assert_writes_settled
      type_continuously(@block)
    end
    assert_selector strip, wait: LIVE
    within(card(@block)) { press "Take over" }
    assert_selector "#{card(@block)} form[data-controller~='admin--saving--autosave'] .ProseMirror[contenteditable=true]", wait: LIVE

    dana_field = nil
    using_session(:dana) do
      assert_selector "#{card(@block)} .ProseMirror[contenteditable=false]", wait: LIVE
      assert_selector "#{card(@block)} [data-editing-strip-text]", text: "Taken over by Olga Braun", wait: LIVE
      locked_at = find("#{card(@block)} .ProseMirror", visible: :all).text
      await_frames
      # The typing goes on (the interval still fires); the field accepts none of it.
      sleep 0.3 # sleep: letting the typist's interval fire several times against a locked field has no event to wait for
      dana_field = find("#{card(@block)} .ProseMirror", visible: :all).text
      assert_equal locked_at, dana_field
      stop_typing
      assert_no_selector "#{card(@block)} [data-editing-kind=lost]"
    end
    assert_includes dana_field, "Start."
    assert_operator dana_field.length, :>, "Start.".length, "nothing was typed through the take-over"
    assert_equal dana_field, find("#{card(@block)} .ProseMirror").text
    assert_equal true, taken_over_events.sole.metadata["answered"]
  end

  test "a holder who is typing in another block still hands this one over, and the other stays editable and saved" do
    other = add_block
    open_page
    join(:dana, @dana) do
      type_in(@block, "First. ")
      assert_writes_settled
      type_in(other, "Second. ")
      assert_writes_settled
      type_continuously(other)
    end
    assert_selector strip(@block), wait: LIVE
    within(card(@block)) { press "Take over" }
    assert_selector "#{card(@block)} form[data-controller~='admin--saving--autosave'] .ProseMirror[contenteditable=true]", text: "First.", wait: LIVE

    assert_equal true, taken_over_events.sole.metadata["answered"]
    using_session(:dana) do
      assert_selector "#{card(other)} .ProseMirror[contenteditable=true]"
      assert_no_selector "#{card(other)} [data-editing-kind]"
      # A tab that never stops typing reads nothing (its reads wait for its writes to be quiet).
      stop_typing
      assert_selector "#{card(@block)} [data-editing-strip-text]", text: "Taken over by Olga Braun", wait: LIVE
      assert_writes_settled
      assert_equal find("#{card(other)} .ProseMirror").text, body_text_of(other).strip
    end
  end

  test "a holder whose save is refused (422) gets its fields back, and is frozen with the notice once it is passed over" do
    open_page
    quick_pass_over
    join(:dana, @dana) do
      type_in(@block, "Saved. ")
      assert_writes_settled
      raise_debounce(card(@block))
      type_in(@block, "Rejected.")
      answer_next("PATCH", "/content_blocks/", 422, "", type: "text/vnd.turbo-stream.html")
      stop_hearing_taken
      record_requests
    end
    assert_selector strip, wait: LIVE
    within(card(@block)) { press "Take over" }
    assert_selector waiting_status, text: "Asking to take over…", wait: LIVE

    using_session(:dana) do
      # The lock went on for the flush and came off when it was refused: typing works again.
      assert_eventually(wait: LIVE, message: "the fields were not given back") { page.evaluate_script("document.querySelector(#{"#{card(@block)} .ProseMirror".to_json}).getAttribute('contenteditable')") == "true" }
      assert_equal [], hand_over_requests
      assert_includes find("#{card(@block)} .ProseMirror").text, "Rejected."
    end
    due
    assert_selector "#{card(@block)} form[data-controller~='admin--saving--autosave'] .ProseMirror[contenteditable=true]", wait: LIVE
    assert_equal false, taken_over_events.sole.metadata["answered"]

    using_session(:dana) do
      hear_taken
      raise_debounce(card(@block), 50)
      find("#{card(@block)} .ProseMirror").send_keys(" More.")
      assert_selector "#{card(@block)} [data-editing-kind=lost] [role=alert]", text: "Olga Braun is editing this block. Your changes weren't saved.", wait: LIVE
      assert_selector "#{card(@block)} .ProseMirror[contenteditable=false]", text: "Rejected."
    end
  end

  test "a request that ends with its holder letting go: the asker claims at once, without waiting out the pass-over time" do
    open_page
    quick_pass_over(60000)
    join(:dana, @dana) do
      type_in(@block, "Dana. ")
      assert_writes_settled
      refuse_to_hand_over
    end
    assert_selector strip, wait: LIVE
    record_requests
    within(card(@block)) { press "Take over" }
    assert_selector waiting_status, text: "Asking to take over…", wait: LIVE

    using_session(:dana) { find("#{card(@block)} button[aria-controls]", text: "Rich text").click }

    assert_selector "#{card(@block)} form[data-controller~='admin--saving--autosave'] .ProseMirror[contenteditable=true]", text: "Dana.", wait: LIVE
    assert held_by(@me)
    assert_equal 2, take_over_requests.size
    assert_equal 0, taken_over_events.count
  end

  test "a third person claiming while I wait ends the waiting, says so, and asks again for nobody" do
    reader = users(:reader)
    held_by_nobody_listening
    open_page
    quick_pass_over
    record_requests
    within(card(@block)) { press "Take over" }
    assert_selector waiting_status, text: "Asking to take over…", wait: LIVE

    Editing::Reservation.of(@block).delete_all
    Editing::Reservation.claim(subject: @block, record: @page, user: reader, tab: "tab-cccccccc")
    Editing::Signals.holder(@page, @block, "claimed")

    assert_selector waiting_status, text: "Someone else is editing this now", wait: LIVE
    assert_no_selector "#{strip} button[disabled]"
    await_frames
    sleep 1 # sleep: proving that no re-ask follows needs a few of the (shortened) pass-over times to pass with nothing to wait for
    assert_equal 1, take_over_requests.size
    assert_equal 0, taken_over_events.count
  end

  test "a take-over that fails for the network or a timeout says it did not work, and the button is ready" do
    held_by_nobody_listening
    open_page
    fail_next("POST", "/take_over")
    within(card(@block)) { press "Take over" }
    assert_selector waiting_status, text: "Couldn't take over. Try again.", wait: LIVE
    assert_no_selector "#{strip} button[disabled]"

    answer_next("POST", "/take_over", 500, "")
    within(card(@block)) { press "Take over" }
    assert_selector waiting_status, text: "Couldn't take over. Try again.", wait: LIVE
    assert_no_selector "#{strip} button[disabled]"
    assert_selector "#{card(@block)} .ProseMirror[contenteditable=false]"
    assert_equal 0, taken_over_events.count
  end

  test "leaving while asking withdraws the request: a visit away, and a page that is closed" do
    open_page
    join(:dana, @dana) do
      type_in(@block, "Dana. ")
      assert_writes_settled
      refuse_to_hand_over
    end
    assert_selector strip, wait: LIVE
    within(card(@block)) { press "Take over" }
    assert_selector waiting_status, text: "Asking to take over…", wait: LIVE
    assert_equal @me.id, Editing::Reservation.of(@block).sole.requested_by_id

    # A Turbo visit.
    click_link "Dashboard"
    assert_eventually(wait: LIVE, message: "the request was not withdrawn by a visit away") { Editing::Reservation.of(@block).sole.requested_by_id.nil? }

    # Closing the page (a full load is the same pagehide).
    open_page
    within(card(@block)) { press "Take over" }
    assert_selector waiting_status, text: "Asking to take over…", wait: LIVE
    assert_equal @me.id, Editing::Reservation.of(@block).sole.requested_by_id
    visit "/cs-studio/pages"
    assert_eventually(wait: LIVE, message: "the request was not withdrawn when the page went") { Editing::Reservation.of(@block).sole.requested_by_id.nil? }
    assert_equal @dana.id, Editing::Reservation.of(@block).sole.user_id
  end

  test "the focus goes to the first field when the person has not moved, and stays where it is when they have" do
    held_by_nobody_listening
    open_page
    quick_pass_over
    within(card(@block)) { press "Take over" }
    assert_selector waiting_status, text: "Asking to take over…", wait: LIVE
    due
    assert_selector "#{card(@block)} form[data-controller~='admin--saving--autosave'] .ProseMirror[contenteditable=true]", wait: LIVE
    assert_eventually(wait: LIVE, message: "the focus never reached the card's first field") { active_in?(card(@block)) }

    # Again, with the person on their way to something else.
    Editing::Reservation.of(@block).delete_all
    held_by_nobody_listening
    open_page
    quick_pass_over
    within(card(@block)) { press "Take over" }
    assert_selector waiting_status, text: "Asking to take over…", wait: LIVE
    find("#page-title").click
    due
    assert_selector "#{card(@block)} form[data-controller~='admin--saving--autosave'] .ProseMirror[contenteditable=true]", wait: LIVE
    assert_equal "page-title", page.evaluate_script("document.activeElement.id")
  end

  test "a change of holder is announced once, to a third person, even when the card is fetched twice" do
    open_page
    join(:dana, @dana) do
      type_in(@block, "Dana. ")
      assert_writes_settled
    end
    join(:reader, users(:reader)) do
      assert_selector strip, text: "Dana Weiss is editing this block", wait: LIVE
      watch_announcements
    end
    assert_selector strip, wait: LIVE
    within(card(@block)) { press "Take over" }
    assert_selector "#{card(@block)} .ProseMirror[contenteditable=true]", wait: LIVE

    using_session(:reader) do
      assert_selector "#{strip}", text: "Olga Braun is editing this block", wait: LIVE
      assert_selector "#{card(@block)} [data-editing-announcer]", text: "Olga Braun took over this block", visible: :all, wait: LIVE
      # Another fetch of the same card (a catch-up) says nothing more.
      page.execute_script("document.getElementById('editing').dispatchEvent(new CustomEvent('admin--editing--hold:refresh', { detail: { subject: 'block-#{@block.id}' } }))")
      assert_writes_settled
      await_frames
      assert_equal [ "Olga Braun took over this block" ], said
      assert_no_selector "[data-editing-kind=lost], [data-editing-kind=deleted]"
    end
  end

  test "in a section: no Take over on the tile, the strip is in the panel, and taking over there clears the tile's avatar" do
    section = add_block(block_type: "section", settings: { "layout" => "two" })
    inside = add_block(section_id: section.id, section_column: 1)
    open_page
    join(:dana, @dana) do
      find("#content_block_#{inside.id} .admin-block-tile__face").click
      type_in(inside, "In a lane", within: panel(inside))
      assert_writes_settled
    end
    assert_selector "#content_block_#{inside.id}[data-editing-held=true]", wait: LIVE
    assert_no_selector "#content_block_#{inside.id} .admin-block-tile button", text: "Take over"
    find("#content_block_#{inside.id} .admin-block-tile__face").click
    assert_selector "#{panel(inside)} [data-editing-kind=held]", text: "Dana Weiss is editing this block"

    within("#{panel(inside)} [data-editing-kind=held]") { press "Take over" }

    assert_selector "#{panel(inside)} form[data-controller~='admin--saving--autosave'] .ProseMirror[contenteditable=true]", text: "In a lane", wait: LIVE
    assert_no_selector "#content_block_#{inside.id}[data-editing-held]", wait: LIVE
    assert_equal 1, taken_over_events.count
  end
end
