require "application_system_test_case"

# Taking over, in the browser (live-editing spec §4.4,
# `controllers/admin/editing/hold_controller.js`): "Take over" asks the
# holder's tab, which sends what it has and lets go; a tab that does not
# answer is passed over after `Editing::PASS_OVER`. Two or three people are two
# or three Capybara sessions (`using_session`). The server's pass-over time is
# set for the whole file (`pass_over`, BEFORE a page is opened: the region
# renders it as a value for the script too); the notice's time is shortened in
# the browser through the region's value. A holder "asleep" is a tab that hears
# no signal (`deafen_tab`) and whose hand-over request is held in a `fetch` stub
# that takes only its own request; a holder that is "gone" is a row made
# through the model with a tab no browser has.
class Admin::EditingTakeOverSystemTest < ApplicationSystemTestCase
  include TestTypes

  LIVE = 8

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @me = users(:one).tap { |user| user.update!(name: "Olga Braun") }
    @dana = users(:two).tap { |user| user.update!(name: "Dana Weiss") }
    @page = create_page(title: "Pricing", published: false)
    @block = add_block
    @original_pass_over = Editing::PASS_OVER
    pass_over(3)
    sign_in_via_form(@me)
  end

  teardown do
    pass_over(@original_pass_over)
    page.execute_script("try { window.localStorage.removeItem('cs-notes-open') } catch (error) {}")
  end

  def pass_over(duration)
    duration = duration.seconds
    Editing.send(:remove_const, :PASS_OVER)
    Editing.const_set(:PASS_OVER, duration)
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
  def answer_next(verb, source, status, body = "")
    page.execute_script(<<~JS, verb, source, status, body)
      const [ verb, source, status, body ] = arguments
      let spent = false
      const real = window.fetch
      window.fetch = function (input, init = {}) {
        const url = typeof input === "string" ? input : input.url
        const method = String(init.method || "GET").toUpperCase()
        if (!spent && method === verb && new RegExp(source).test(url)) {
          spent = true
          return Promise.resolve(new Response(body, { status }))
        }
        return real.apply(this, arguments)
      }
    JS
  end

  # This tab hears no news that the block was taken, and nothing else changes
  # it: a laptop with its lid half shut (it still hears when it is asked to
  # hand over). `undeafen_tab` puts the hearing back.
  def deafen_tab
    page.execute_script(<<~JS)
      const live = window.Stimulus.getControllerForElementAndIdentifier(document.getElementById('editing'), 'admin--editing--live')
      const heard = Object.getPrototypeOf(live).heard
      live.heard = (signal) => { if (signal.kind === "holder" && signal.reason === "requested") heard.call(live, signal) }
    JS
  end

  def undeafen_tab
    page.execute_script(<<~JS)
      const live = window.Stimulus.getControllerForElementAndIdentifier(document.getElementById('editing'), 'admin--editing--live')
      delete live.heard
    JS
  end

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
    pass_over(1)
    held_by_nobody_listening
    assert @block.reload && Editing::Reservation.holder_of(@block).user_id == @dana.id
    open_page
    record_requests
    assert_selector strip, text: "Dana Weiss is editing this block"

    within(card(@block)) { press "Take over" }

    assert_selector "#{card(@block)} form[data-controller~='admin--saving--autosave'] .ProseMirror[contenteditable=true]", wait: LIVE
    assert_no_selector strip
    assert held_by(@me)
    assert_equal 2, take_over_requests.size
    assert_equal 0, hand_over_requests.size
    event = Audit::Event.where(action: "block.taken_over").sole
    assert_equal({ "from_user_id" => @dana.id, "to_user_id" => @me.id, "answered" => false }, event.metadata)
    assert_equal 1, taken_over_events.count
    visit admin_audit_events_path
    assert_text "took over editing"
  end

  test "a tab that wakes after it was passed over keeps its unsaved text, read-only, with the notice" do
    pass_over(1)
    open_page
    join(:dana, @dana) do
      type_in(@block, "Saved. ")
      assert_writes_settled
      raise_debounce(card(@block))
      type_in(@block, "Typed while asleep. ")
      deafen_tab
      delay_next("POST", "/hand_over")
    end
    assert_selector strip, text: "Dana Weiss is editing this block", wait: LIVE

    within(card(@block)) { press "Take over" }
    assert_selector "#{card(@block)} form[data-controller~='admin--saving--autosave'] .ProseMirror[contenteditable=true]", wait: LIVE
    assert_equal 1, taken_over_events.count

    using_session(:dana) do
      await_delayed
      send_delayed
      undeafen_tab
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

  test "a tab that wakes after it was passed over with nothing unsaved shows the block as held by me" do
    pass_over(1)
    open_page
    join(:dana, @dana) do
      type_in(@block, "All saved. ")
      assert_writes_settled
      deafen_tab
      delay_next("POST", "/hand_over")
    end
    assert_selector strip, wait: LIVE
    within(card(@block)) { press "Take over" }
    assert_selector "#{card(@block)} .ProseMirror[contenteditable=true]", wait: LIVE

    using_session(:dana) do
      await_delayed
      send_delayed
      undeafen_tab
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
    pass_over(1)
    held_by_nobody_listening
    open_page
    record_requests
    page.execute_script("const button = document.querySelector(#{"#{strip} button".to_json}); button.click(); button.click(); button.click()")

    assert_selector "#{card(@block)} form[data-controller~='admin--saving--autosave'] .ProseMirror[contenteditable=true]", wait: LIVE
    # One press, and the one request after the pass-over time that the server wanted.
    assert_equal 2, take_over_requests.size
    assert_equal 1, taken_over_events.count
  end

  test "the holder cannot hand over: nothing is handed over while text cannot be saved, the pass-over happens, and the holder's text is kept, frozen with the notice" do
    pass_over(2)
    open_page
    join(:dana, @dana) do
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

  test "typing through the hand-over: everything typed is either in the block that is handed over or still in the holder's field with the notice for lost text" do
    open_page
    join(:dana, @dana) do
      type_in(@block, "Start. ")
      assert_writes_settled
      # A person typing a letter every 150 ms for a few seconds, into the field.
      page.execute_script(<<~JS)
        const editor = document.querySelector(#{"#{card(@block)} .ProseMirror".to_json})
        window.__letters = 0
        window.__typing = setInterval(() => {
          if (editor.getAttribute("contenteditable") !== "true") return
          editor.focus()
          const range = document.createRange()
          range.selectNodeContents(editor)
          range.collapse(false)
          getSelection().removeAllRanges()
          getSelection().addRange(range)
          document.execCommand("insertText", false, "x")
          window.__letters += 1
        }, 150)
      JS
    end
    assert_selector strip, wait: LIVE
    within(card(@block)) { press "Take over" }
    assert_selector "#{card(@block)} form[data-controller~='admin--saving--autosave'] .ProseMirror[contenteditable=true]", wait: LIVE

    dana_field = nil
    using_session(:dana) do
      assert_selector "#{card(@block)} .ProseMirror[contenteditable=false]", wait: LIVE
      page.execute_script("clearInterval(window.__typing)")
      await_frames
      dana_field = find("#{card(@block)} .ProseMirror", visible: :all).text
    end
    mine = find("#{card(@block)} .ProseMirror").text
    # What the new holder has is a prefix of what the old holder's field shows: nothing typed is gone,
    # and whatever came after the last save is in the field with the notice for lost text.
    assert dana_field.start_with?("Start."), "the field reads #{dana_field.inspect}"
    assert dana_field.start_with?(mine), "the field shows less than the new holder has: #{dana_field.inspect} / #{mine.inspect}"
    using_session(:dana) do
      if dana_field == mine
        assert_no_selector "#{card(@block)} [data-editing-kind=lost]"
      else
        assert_selector "#{card(@block)} [data-editing-kind=lost] [role=alert]", wait: LIVE
      end
    end
    assert_equal true, taken_over_events.sole.metadata["answered"]
  end

  test "the focus goes to the first field when the person has not moved, and stays where it is when they have" do
    pass_over(1)
    held_by_nobody_listening
    open_page
    within(card(@block)) { press "Take over" }
    assert_selector "#{card(@block)} form[data-controller~='admin--saving--autosave'] .ProseMirror[contenteditable=true]", wait: LIVE
    assert_eventually(wait: LIVE, message: "the focus never reached the card's first field") { active_in?(card(@block)) }

    # Again, with the person on their way to something else.
    Editing::Reservation.of(@block).delete_all
    held_by_nobody_listening
    open_page
    within(card(@block)) { press "Take over" }
    find("#page-title").click
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
