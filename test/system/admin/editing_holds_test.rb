require "application_system_test_case"

# A tab claims what it starts to change, lets go when it is done, and keeps a
# refused text for copying (live-editing spec §4.2 to §4.4,
# `controllers/admin/editing/hold_controller.js`). Two people are two Capybara
# sessions (`using_session`); `await_notes_live` waits for an editor's
# subscription, so a signal caused afterwards is heard. A colleague's claim made
# "from outside the browser" is the model's, which sends no signal; one made by
# typing is the real thing.
#
# The hold's clock is moved with `update_all` (`expire`); the strip's time in
# the browser is shortened by rewriting `data-editing-expires-in` on a strip
# and putting a copy in its place (`shorten`): the controller reads it when the
# strip connects. A `fetch` stub takes only its own request and passes every
# other one through.
class Admin::EditingHoldsSystemTest < ApplicationSystemTestCase
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

  def doc(text) = { "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => text } ] } ] }

  def type_in(block, text, within: card(block))
    find("#{within} .ProseMirror").click
    find("#{within} .ProseMirror").send_keys(text)
  end

  # Text typed into a form that no timer will send and nothing will flush:
  # unsaved, but not outstanding (the live script's reads wait for the write
  # queue to be quiet, which a debounce still running would hold up). The
  # claim of the first change is sent all the same.
  def type_unsent(block, text, within: card(block))
    form = autosave_form(within).to_json
    page.execute_script("const a = window.Stimulus.getControllerForElementAndIdentifier(document.querySelector(#{form}), 'admin--saving--autosave'); a.saveNow = () => {}")
    type_in(block, text, within: within)
    page.execute_script("const a = window.Stimulus.getControllerForElementAndIdentifier(document.querySelector(#{form}), 'admin--saving--autosave'); clearTimeout(a.timer); a.timer = null")
  end

  def expire(subject = @block)
    Editing::Reservation.of(subject).update_all(changed_at: 3.minutes.ago) # version: none (a system test moves a reservation's clock)
  end

  def held_by(user, subject = @block) = Editing::Reservation.holder_of(subject)&.user_id == user.id

  def body_of(block) = block.reload.body_document(locale: "en").to_json

  def autosave_form(within) = "#{within} form[data-controller~='admin--saving--autosave']"

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

  def claims = sent.grep(%r{/editing/\w+/\d+/claim\z})

  def releases = sent.grep(%r{/editing/\w+/\d+/release\z})

  def patches = sent.grep(/\APATCH /)

  # Holds the NEXT request of `verb` whose URL matches `source` (a regexp's
  # text) BEFORE it is sent: it reaches the server only at `send_delayed`. For
  # a tie, or a save that arrives after the hold has been taken.
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

  CLAIM = '/editing/(page|post)/\\d+/claim(\\?.*)?$'.freeze

  def stub_clipboard(fail: false)
    page.execute_script(<<~JS, fail)
      const [ fail ] = arguments
      window.__copied = null
      Object.defineProperty(navigator, "clipboard", { configurable: true, value: { writeText: (text) => { if (fail) return Promise.reject(new Error("denied")); window.__copied = text; return Promise.resolve() } } })
    JS
  end

  def copied = page.evaluate_script("window.__copied")

  # Puts the strip's time in the page at `milliseconds` and puts a copy in its
  # place, so that the controller (which reads it when a strip connects) arms
  # its timer with that.
  def shorten(selector, milliseconds)
    page.execute_script(<<~JS, selector, milliseconds)
      const [ selector, milliseconds ] = arguments
      const strip = document.querySelector(selector)
      strip.dataset.editingExpiresIn = String(milliseconds)
      strip.replaceWith(strip.cloneNode(true))
    JS
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

  def region_set(name, value) = page.execute_script("document.getElementById('editing').setAttribute('data-admin--editing--hold-#{name}-value', #{value.to_json})")

  # Typing a block in a tie: this tab's claim is held until the colleague has
  # claimed through the model, then let go and refused.
  def lose_a_tie(block = @block, text = "My words", within: card(block))
    open_page
    record_requests
    delay_next("POST", CLAIM)
    type_in(block, text, within: within)
    await_delayed
    Editing::Reservation.claim(subject: block, record: @page, user: @dana, tab: "tab-dddddddd")
    send_delayed
  end

  # --- the brief's -----------------------------------------------------------

  test "typing in a block makes it read-only for the colleague, with who holds it, and closing or leaving frees it" do
    join(:dana, @dana)
    open_page
    type_in(@block, "Prices")
    assert_writes_settled
    assert held_by(@me)

    using_session(:dana) do
      assert_selector "#{card(@block)}[data-editing-held=true] [data-editing-kind=held]", text: "Olga Braun is editing this block", wait: LIVE
      assert_no_selector "#{card(@block)} form[data-controller~='admin--saving--autosave']"
      assert_no_selector "#{card(@block)} [role=toolbar]"
      assert_selector "#{card(@block)} .ProseMirror[contenteditable=false]", text: "Prices"
    end

    visit "/cs-studio/pages"
    using_session(:dana) do
      assert_no_selector "#{card(@block)}[data-editing-held]", wait: LIVE
      assert_selector "#{card(@block)} form[data-controller~='admin--saving--autosave']"
    end
    assert_not held_by(@me)
  end

  # Takes the write queue's turn with a write of the test's own and keeps it
  # until `free_queue`: whatever is sent through the queue meanwhile waits.
  def occupy_queue
    page.execute_script(<<~JS)
      window.__occupied = false
      import("saving/queue").then(({ enqueue }) => enqueue(() => { window.__occupied = true; return new Promise((resolve) => { window.__free = resolve }) }))
    JS
    await_js "window.__occupied === true"
  end

  def free_queue = page.execute_script("window.__free()")

  # A JS expression about the autosave controller of the form in `within`.
  def autosave_js_of(within, expression)
    "(() => { const form = document.querySelector(#{autosave_form(within).to_json}); const autosave = form && window.Stimulus.getControllerForElementAndIdentifier(form, 'admin--saving--autosave'); return Boolean(autosave && (#{expression})) })()"
  end

  HOLD_JS = "window.Stimulus.getControllerForElementAndIdentifier(document.getElementById('editing'), 'admin--editing--hold')".freeze

  # No pause will save: the form's own debounce value is put out of reach, so
  # "nothing was saved" does not depend on how fast the keys arrive.
  def raise_debounce(within, ms = 600000)
    page.execute_script("document.querySelector(#{autosave_form(within).to_json}).setAttribute('data-admin--saving--autosave-debounce-value', #{ms})")
  end

  # The hold script's own clock for a subject, put back past half a hold: what
  # "this tab claimed it long ago" is, without waiting the time out.
  def age_claim(block = @block)
    page.execute_script("(() => { const hold = #{HOLD_JS}; hold.held.set('block-#{block.id}', Date.now() - hold.holdValue) })()")
  end

  def await_claims(count)
    assert_eventually(wait: LIVE, message: "expected #{count} claims: #{sent.inspect}") { claims.size == count }
    await_js "!#{HOLD_JS}.claiming.has('block-#{@block.id}')", wait: LIVE
  end

  test "the claim is sent through the write queue, ahead of the block's first save, and once for three bursts of typing" do
    open_page
    record_requests
    # THROUGH THE QUEUE, not only first (final review I8: a bare `fetch` at the
    # first change would also come before a save that waits out its debounce).
    # A write of the test's own has the queue's turn: the claim is made, and
    # is not sent until that write is answered.
    occupy_queue
    type_in(@block, "One")
    await_js "#{HOLD_JS}.claiming.has('block-#{@block.id}')"
    await_frames
    assert_equal [], sent, "the claim was sent beside the write queue, while another write had its turn"
    free_queue
    assert_eventually(wait: LIVE, message: "the claim was never sent once the queue was free") { claims.size == 1 }
    assert_writes_settled
    type_in(@block, " two")
    assert_writes_settled
    type_in(@block, " three")
    assert_writes_settled

    assert_equal 1, claims.size, "claims: #{sent.inspect}"
    assert_operator sent.index(claims.first), :<, sent.index(patches.first), sent.inspect
    assert_operator patches.size, :>=, 3
    assert_includes body_of(@block), "One two three"
  end

  test "reading reserves nothing: opening, focusing and leaving a field without a change sends no claim" do
    open_page
    record_requests
    find("#{card(@block)} .ProseMirror").click
    find("#page-title").click
    find("#{card(@block)} .ProseMirror").click
    find("body").click
    await_frames
    assert_writes_settled

    assert_equal [], sent
    assert_not Editing::Reservation.of(@block).exists?
  end

  test "closing a block's form in a section releases it, after its last save, and the colleague's tile loses its avatar" do
    section = add_block(block_type: "section", settings: { "layout" => "two" })
    inside = add_block(section_id: section.id, section_column: 1)
    join(:dana, @dana)
    open_page
    record_requests
    find("#content_block_#{inside.id} .admin-block-tile__face").click
    type_in(inside, "In a lane", within: panel(inside))
    assert_writes_settled
    assert held_by(@me, inside)

    using_session(:dana) do
      assert_selector "#content_block_#{inside.id}[data-editing-held=true]", wait: LIVE
      find("#content_block_#{inside.id} .admin-block-tile__face").click
      assert_selector "#{panel(inside)} [data-editing-kind=held]", text: "Olga Braun is editing this block"
      assert_no_selector "#{panel(inside)} form[data-controller~='admin--saving--autosave']"
    end

    within(panel(inside)) { click_button "Close" }
    assert_eventually(wait: LIVE, message: "the block was not released") { !Editing::Reservation.of(inside).exists? }

    assert_equal 3, %w[POST PATCH POST].zip(%w[claim content_blocks release]).map { |verb, part| sent.find { |each| each.start_with?(verb) && each.include?(part) } }.compact.size
    assert_operator sent.index(patches.last), :<, sent.index(releases.last), sent.inspect
    using_session(:dana) do
      assert_no_selector "#content_block_#{inside.id}[data-editing-held]", wait: LIVE
      assert_no_selector "#{panel(inside)} [data-editing-kind=held]", wait: LIVE
    end
  end

  test "a held block in a section shows its holder's avatar on the tile, and opening the tile shows the strip" do
    section = add_block(block_type: "section", settings: { "layout" => "two" })
    inside = add_block(section_id: section.id, section_column: 1)
    tile = "#content_block_#{inside.id}"
    join(:dana, @dana)
    open_page
    find("#{tile} .admin-block-tile__face").click
    type_in(inside, "In a lane", within: panel(inside))
    assert_writes_settled
    assert held_by(@me, inside)

    using_session(:dana) do
      # The tile is drawn for her by the signal, not by a reload; the avatar is
      # a hover-only tooltip's host, so its words are read from the DOM.
      assert_selector "#{tile}[data-editing-held=true] [data-holder-avatar]", wait: LIVE
      assert_equal "OB", find("#{tile} [data-holder-avatar]").find("span[aria-hidden=true]:not([data-tooltip])", match: :first).text
      assert_selector "#{tile} [data-holder-avatar] .sr-only", text: "Olga Braun is editing this block", visible: :all
      assert_selector "#{tile} [data-holder-avatar] [data-tooltip]", text: "Olga Braun is editing this block", visible: :all
      assert_operator evaluate_script("(() => { const t = document.querySelector(#{tile.to_json}); return t.querySelector('[data-holder-avatar]').compareDocumentPosition(t.querySelector('.admin-notes-marker')) & Node.DOCUMENT_POSITION_FOLLOWING })()"), :>, 0
      assert_no_selector "#{tile} button", text: "Take over", visible: :all
      assert_no_selector "#{tile} [aria-live]", visible: :all

      find("#{tile} .admin-block-tile__face").click
      assert_selector "#{panel(inside)} [data-editing-kind=held]", text: "Olga Braun is editing this block"
    end

    within(panel(inside)) { click_button "Close" }
    assert_eventually(wait: LIVE, message: "the block was not released") { !Editing::Reservation.of(inside).exists? }
    using_session(:dana) do
      assert_no_selector "#{tile} [data-holder-avatar]", wait: LIVE
    end
  end

  test "collapsing a card releases it" do
    join(:dana, @dana)
    open_page
    record_requests
    type_in(@block, "Collapse me")
    find("#{card(@block)} [data-action*='admin--editor--blocks#toggle']", match: :first).click
    assert_eventually(wait: LIVE, message: "the block was not released") { !Editing::Reservation.of(@block).exists? }

    assert_equal 1, releases.size
    assert_operator sent.index(patches.last), :<, sent.index(releases.last), sent.inspect
    assert_includes body_of(@block), "Collapse me"
    using_session(:dana) { assert_no_selector "#{card(@block)}[data-editing-held]", wait: LIVE }
  end

  test "an expired hold frees the colleague's card without anyone doing anything" do
    open_page
    type_in(@block, "Holding")
    assert_writes_settled
    join(:dana, @dana) do
      assert_selector "#{card(@block)}[data-editing-held=true]", wait: LIVE
      assert_operator page.evaluate_script("Number(document.querySelector('#{card(@block)} [data-editing-kind=held]').dataset.editingExpiresIn)"), :>, 60_000
      expire
      shorten("#{card(@block)} [data-editing-kind=held]", 200)
      assert_selector "#{card(@block)} form[data-controller~='admin--saving--autosave']", wait: LIVE
      assert_no_selector "#{card(@block)}[data-editing-held]"
      assert_no_selector "#{card(@block)} [data-editing-kind=held]"
    end
  end

  test "while the holder is still there, an expired-looking strip is drawn again with a new time" do
    open_page
    type_in(@block, "Holding")
    assert_writes_settled
    join(:dana, @dana) do
      assert_selector "#{card(@block)}[data-editing-held=true]", wait: LIVE
      # A renewal sends no signal: the row moves, nobody is told.
      Editing::Reservation.of(@block).update_all(changed_at: Time.current) # version: none (a system test moves a reservation's clock)
      shorten("#{card(@block)} [data-editing-kind=held]", 300)
      assert_eventually(wait: LIVE, message: "the strip was never drawn again with a new time") do
        page.evaluate_script("Number(document.querySelector('#{card(@block)} [data-editing-kind=held]')?.dataset.editingExpiresIn || 0)") > 60_000
      end
      assert_selector "#{card(@block)}[data-editing-held=true]"
    end
  end

  test "a hidden document does not fetch when a hold runs out, and catches up when it is seen" do
    open_page
    type_in(@block, "Holding")
    assert_writes_settled
    join(:dana, @dana) do
      assert_selector "#{card(@block)}[data-editing-held=true]", wait: LIVE
      page.execute_script(<<~JS)
        window.__gets = []
        const real = window.fetch
        window.fetch = function (input) { const url = typeof input === "string" ? input : input.url; if (url.includes("/cs-studio/editing/")) window.__gets.push(url); return real.apply(this, arguments) }
      JS
      page.execute_script("window.__due = 0; document.getElementById('editing').addEventListener('admin--editing--hold:refresh', () => { window.__due += 1 })")
      hide_document
      expire
      shorten("#{card(@block)} [data-editing-kind=held]", 200)
      # The timer has fired while the document was hidden: the part was asked for, and nothing was fetched.
      await_js "window.__due >= 1"
      await_frames
      assert_equal [], page.evaluate_script("window.__gets")
      assert_no_selector "#{card(@block)} form[data-controller~='admin--saving--autosave']"
      show_document
      assert_selector "#{card(@block)} form[data-controller~='admin--saving--autosave']", wait: LIVE
    end
  end

  test "when a hold lapsed and the colleague changed the block, my open form shows their text, read-only, held by them" do
    open_page
    type_in(@block, "Mine")
    assert_writes_settled
    expire
    join(:dana, @dana) do
      assert_selector "#{card(@block)} form[data-controller~='admin--saving--autosave']"
      type_in(@block, "Hers")
      assert_writes_settled
    end

    assert_selector "#{card(@block)}[data-editing-held=true] [data-editing-kind=held]", text: "Dana Weiss is editing this block", wait: LIVE
    assert_selector "#{card(@block)} .ProseMirror[contenteditable=false]", text: "Hers"
    assert_no_selector "#{card(@block)} form[data-controller~='admin--saving--autosave']"
  end

  test "a tie: my claim loses, my text stays in read-only fields with the notice, Copy my text copies it and Discard shows the block as it is" do
    lose_a_tie
    assert_selector "#{card(@block)} [role=alert]", text: "Dana Weiss is editing this block. Your changes weren't saved.", wait: LIVE
    assert_selector "#{card(@block)} .ProseMirror[contenteditable=false]", text: "My words"
    assert_equal [], patches, "the save queued behind the refused claim was sent"
    assert_equal "true", page.evaluate_script("document.querySelector(#{autosave_form(card(@block)).to_json}).dataset.editingFrozen")
    assert_not_includes body_of(@block), "My words"

    stub_clipboard
    within("#{card(@block)} [data-editing-kind]") { click_button "Copy my text" }
    assert_selector "#{card(@block)} [data-editing-copied]", text: "Copied", wait: LIVE
    assert_equal "My words", copied

    within("#{card(@block)} [data-editing-kind]") { click_button "Discard" }
    assert_selector "#{card(@block)}[data-editing-held=true] [data-editing-kind=held]", text: "Dana Weiss is editing this block", wait: LIVE
    assert_no_text "My words"
    assert_no_selector "[data-editing-kind=lost]"
    assert_writes_settled
    assert_equal [], patches
  end

  test "Copy my text says so when the clipboard refuses, and 'Copied' is gone after two seconds" do
    lose_a_tie
    assert_selector "#{card(@block)} [role=alert]", wait: LIVE
    stub_clipboard(fail: true)
    within("#{card(@block)} [data-editing-kind]") { click_button "Copy my text" }
    assert_selector "#{card(@block)} [data-editing-copied]", text: "Couldn't copy. Select the text and copy it yourself.", wait: LIVE
    stub_clipboard
    within("#{card(@block)} [data-editing-kind]") { click_button "Copy my text" }
    assert_selector "#{card(@block)} [data-editing-copied]", text: "Copied", wait: LIVE
    assert_no_selector "#{card(@block)} [data-editing-copied]:not(:empty)", wait: 5
  end

  test "a save refused because the hold lapsed and was taken keeps the text, read-only, with the notice" do
    open_page
    type_in(@block, "First")
    assert_writes_settled
    assert_includes body_of(@block), "First"
    delay_next("PATCH", "/content_blocks/#{@block.id}")
    type_in(@block, " second")
    await_delayed
    expire
    Editing::Reservation.claim(subject: @block, record: @page, user: @dana, tab: "tab-dddddddd")
    send_delayed

    assert_selector "#{card(@block)} [role=alert]", text: "Dana Weiss is editing this block. Your changes weren't saved.", wait: LIVE
    assert_selector "#{card(@block)} .ProseMirror[contenteditable=false]", text: "First second"
    assert_includes body_of(@block), "First"
    assert_not_includes body_of(@block), "second"
    assert_selector "#block-#{@block.id}-save-status", text: /NOT SAVED/i
    assert_selector "[data-editing-kind=lost]", count: 1
  end

  test "a hold that this tab claimed long ago is claimed again on the first change, and refused when it was taken meanwhile" do
    open_page
    record_requests
    type_in(@block, "First")
    assert_writes_settled
    assert_equal 1, claims.size
    # "Long ago" is the script's own clock for this subject, put back, not a
    # time waited out (final review I9: the wait was a sleep by another name,
    # and five keys slower than half the shortened hold claimed twice).
    age_claim
    expire
    Editing::Reservation.claim(subject: @block, record: @page, user: @dana, tab: "tab-dddddddd")
    # The first key sends the claim, and its refusal freezes the field: keys
    # that arrive after it do not go in, which is right, and how many do is the
    # machine's choice (CI, 2026-10-11: "First lat"). So the claim is held, as
    # in every tie here, until the whole text is in the field.
    delay_next("POST", CLAIM)
    type_in(@block, " later")
    await_delayed
    send_delayed

    assert_selector "#{card(@block)} [role=alert]", text: "Dana Weiss is editing this block. Your changes weren't saved.", wait: LIVE
    assert_equal 2, claims.size
    assert_equal 1, patches.size, "only the first text was saved"
    assert_selector "#{card(@block)} .ProseMirror[contenteditable=false]", text: "First later"
  end

  test "a block deleted under my unsaved text: the notice names who deleted it, Copy my text works and Remove takes the card away" do
    open_page
    type_unsent(@block, "Unsaved words")
    as(@dana, channel: :admin) { ContentBlocks::Destroy.call(@block) }

    assert_selector "#{card(@block)} [role=alert]", text: "Dana Weiss deleted this block. Your changes weren't saved.", wait: LIVE
    assert_selector "#{card(@block)} .ProseMirror[contenteditable=false]", text: "Unsaved words"
    stub_clipboard
    within("#{card(@block)} [data-editing-kind]") { click_button "Copy my text" }
    assert_selector "#{card(@block)} [data-editing-copied]", text: "Copied", wait: LIVE
    assert_equal "Unsaved words", copied

    within("#{card(@block)} [data-editing-kind]") { click_button "Remove" }
    assert_no_selector card(@block)
    assert_writes_settled
  end

  test "a block deleted together with its section, under my unsaved text in its open panel, gets the same notice" do
    section = add_block(block_type: "section", settings: { "layout" => "two" })
    inside = add_block(section_id: section.id, section_column: 1)
    open_page
    find("#content_block_#{inside.id} .admin-block-tile__face").click
    type_unsent(inside, "Lane text", within: panel(inside))
    as(@dana, channel: :admin) { ContentBlocks::Destroy.call(section) }

    assert_selector "#{panel(inside)} [role=alert]", text: "Dana Weiss deleted this block. Your changes weren't saved.", wait: LIVE
    assert_selector "#{panel(inside)} .ProseMirror[contenteditable=false]", text: "Lane text"
    within("#{panel(inside)} [data-editing-kind]") { click_button "Remove" }
    assert_no_selector panel(inside)
    assert_writes_settled
  end

  test "my own second tab is someone else: 'You're editing this in another tab'" do
    using_session(:other) do
      sign_in_via_form(@me)
      visit "/cs-studio/pages/#{@page.id}"
      await_notes_live
    end
    open_page
    type_in(@block, "Here")
    assert_writes_settled

    using_session(:other) do
      assert_selector "#{card(@block)}[data-editing-held=true] [data-editing-kind=held]", text: "You're editing this in another tab", wait: LIVE
      assert_selector "#{card(@block)} [data-editing-kind=held] span.bg-ink.text-paper[aria-hidden=true]", wait: LIVE
      assert_equal 0, page.all("#editor-notice > *").size
    end
  end

  test "reloading the editor frees what this tab held, and the block is editable again without a click" do
    open_page
    type_in(@block, "Before")
    assert_writes_settled
    assert held_by(@me)

    page.refresh
    await_notes_live
    assert_no_selector "[data-editing-kind=held]", wait: LIVE
    assert_selector "#{card(@block)} form[data-controller~='admin--saving--autosave']"
    type_in(@block, " after")
    assert_writes_settled
    assert_includes body_of(@block), "Before after"
    assert held_by(@me)
  end

  test "a Turbo visit away releases what this tab held, and Back to the editor shows no strip of my own" do
    open_page
    type_in(@block, "Before")
    assert_writes_settled
    assert held_by(@me)

    click_frame_link { click_link "Posts" }
    assert_eventually(wait: LIVE, message: "the Turbo visit away did not release the block") { !Editing::Reservation.of(@block).exists? }
    page.go_back
    await_notes_live
    assert_no_selector "[data-editing-kind=held]"
    type_in(@block, " after")
    assert_writes_settled
    assert_includes body_of(@block), "Before after"
  end

  test "a reader's editor claims nothing and shows who is editing, without Take over" do
    join(:reader, users(:reader))
    open_page
    type_in(@block, "Writers")
    assert_writes_settled

    using_session(:reader) do
      assert_selector "#{card(@block)}[data-editing-held=true] [data-editing-kind=held]", text: "Olga Braun is editing this block", wait: LIVE
      assert_no_selector "#{card(@block)} [data-editing-kind=held] button", text: "Take over"
    end
  end

  test "the page settings are held like a block" do
    join(:dana, @dana)
    open_page
    find("#page-title").fill_in(with: "Pricing 2")
    assert_writes_settled
    assert held_by(@me, @page)

    using_session(:dana) do
      assert_selector "#page-hold [data-editing-kind=held]", text: "Olga Braun is editing the page settings", wait: LIVE
      assert_selector "#page-title[readonly]"
      assert_no_selector "#page-settings form[data-controller~='admin--saving--autosave']"
    end
  end

  test "a post is held like a block: the strip stands in the notice area and the form is read-only" do
    post = create_post(title: "Hello", published: false)
    join(:dana, @dana, path: "/cs-studio/posts/#{post.id}")
    visit "/cs-studio/posts/#{post.id}"
    await_notes_live
    find("input[name='post[title]']").fill_in(with: "Hello again")
    assert_writes_settled

    using_session(:dana) do
      assert_selector "#editor-notice [data-editing-kind=held]", text: "Olga Braun is editing this post", wait: LIVE
      assert_selector "#post-form input[name='post[title]'][readonly]"
      assert_no_selector "#post-form[data-controller~='admin--saving--autosave']"
    end
  end

  test "a post's lost claim shows the notice in the notice area when the form is not stale" do
    post = create_post(title: "Hello", published: false)
    visit "/cs-studio/posts/#{post.id}"
    await_notes_live
    record_requests
    delay_next("POST", CLAIM)
    find("input[name='post[title]']").fill_in(with: "Mine")
    await_delayed
    Editing::Reservation.claim(subject: post, record: post, user: @dana, tab: "tab-dddddddd")
    send_delayed

    assert_selector "#editor-notice [data-editing-kind=lost] [role=alert]", text: "Dana Weiss is editing this post. Your changes weren't saved.", wait: LIVE
    assert_selector "input[name='post[title]'][readonly]"
    assert_equal [], patches
  end

  test "a post whose form is stale keeps the Changed elsewhere bar when a hold's notice arrives" do
    post = create_post(title: "Hello", published: false)
    visit "/cs-studio/posts/#{post.id}"
    await_notes_live
    backdate(post)
    # The colleague's save the editor does not hear of: the next save is stale.
    as_unheard(@dana, channel: :admin) { Posts::Save.call(post.reload, translations: { "en" => { title: "Theirs" } }) }
    find("input[name='post[title]']").fill_in(with: "Mine")
    assert_selector "#editor-notice #changed-elsewhere", wait: LIVE

    # Somebody holds the post now; this tab's form is dead until a reload, and
    # whatever else is true the bar stays: its form cannot be stale AND get a
    # claim refused in the other order, because a held post has no autosave.
    expire(post)
    Editing::Reservation.claim(subject: post, record: post, user: @dana, tab: "tab-dddddddd")
    # This tab's own claim of a moment ago was the first change's; asked again by hand.
    page.execute_script("const hold = window.Stimulus.getControllerForElementAndIdentifier(document.getElementById('editing'), 'admin--editing--hold'); hold.held.delete('record'); hold.claim('record')")
    assert_eventually(wait: LIVE, message: "the claim was never refused") { page.evaluate_script("document.querySelector('#post-form').dataset.editingFrozen") == "true" }
    await_frames

    assert_selector "#editor-notice #changed-elsewhere"
    assert_no_selector "#editor-notice [data-editing-kind]"
  end

  test "a held page's blocks can still be added, moved and deleted by the colleague, and my form keeps my text" do
    second = add_block
    open_page
    type_unsent(@block, "Unsent but held")
    join(:dana, @dana) do
      find("#{card(@block)} button[aria-label='Block actions']").click
      within(card(@block)) { click_button "Move down" }
      assert_writes_settled
    end
    assert_eventually(wait: LIVE, message: "the move was not saved") { BlockOutline.new(@page.content_blocks.reload).top_level.map(&:id) == [ second.id, @block.id ] }
    added = as(@dana, channel: :admin) { ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" }).record }
    as(@dana, channel: :admin) { ContentBlocks::Destroy.call(second) }

    assert_selector card(added), wait: LIVE
    assert_no_selector card(second), wait: LIVE
    assert_selector "#{card(@block)} .ProseMirror", text: "Unsent but held"
    assert_selector "#{card(@block)} .ProseMirror[contenteditable=true]"
  end

  test "leaving the editor with a held block asks nothing and loses nothing" do
    open_page
    type_in(@block, "Held text")
    assert_writes_settled
    join(:dana, @dana) do
      assert_selector "#{card(@block)}[data-editing-held=true]", wait: LIVE
      click_frame_link { click_link "Posts" }
      assert_no_selector "dialog[open]"
      assert_equal "/cs-studio/posts", page.current_path
    end
    click_frame_link { click_link "Posts" }
    assert_no_selector "dialog[open]"
    assert_includes body_of(@block), "Held text"
  end

  # --- the frozen form is safe -----------------------------------------------

  test "Enter and typing in a frozen form send nothing, its controls are dead, and its autosave is paused with nothing queued" do
    list = add_block(block_type: "post_list", settings: { "limit" => 3 })
    open_page
    record_requests
    delay_next("POST", CLAIM)
    find("#block-#{list.id}-limit").fill_in(with: "7")
    await_delayed
    Editing::Reservation.claim(subject: list, record: @page, user: @dana, tab: "tab-dddddddd")
    send_delayed
    assert_selector "#{card(list)} [role=alert]", text: "Dana Weiss is editing this block. Your changes weren't saved.", wait: LIVE

    page.execute_script("window.__marker = 'same document'")
    url = page.current_url
    limit = find("#block-#{list.id}-limit")
    assert limit[:readonly]
    limit.send_keys(:backspace, "9", :enter)
    await_frames

    assert_equal "7", limit.value
    assert_equal "same document", page.evaluate_script("window.__marker")
    assert_equal url, page.current_url
    assert_equal [], patches
    assert_equal 3, list.reload.settings["limit"].to_i
    form = autosave_form(card(list))
    assert page.evaluate_script("(() => { const form = document.querySelector(#{form.to_json}); const a = window.Stimulus.getControllerForElementAndIdentifier(form, 'admin--saving--autosave'); return a.paused && !a.timer && !a.pending && !a.outstanding() })()")
    assert page.evaluate_script("Array.from(document.querySelectorAll(#{"#{form} select, #{form} button:not([data-held-guard])".to_json})).every((control) => control.disabled)")
    assert page.evaluate_script("document.querySelector(#{"#{form} [data-held-guard]".to_json}).disabled")
  end

  test "a frozen form's data-action tokens are the server's allow-list, from the same list" do
    list = add_block(block_type: "post_list", settings: { "limit" => 3 })
    open_page
    delay_next("POST", CLAIM)
    find("#block-#{list.id}-limit").fill_in(with: "7")
    await_delayed
    Editing::Reservation.claim(subject: list, record: @page, user: @dana, tab: "tab-dddddddd")
    send_delayed
    assert_selector "#{card(list)} [role=alert]", wait: LIVE

    kept = page.evaluate_script("Array.from(document.querySelectorAll(#{"#{card(list)} form [data-action]".to_json})).flatMap((each) => each.dataset.action.split(/\\s+/))")
    kept.each do |token|
      action = Admin::EditorScreen::HeldFields.action_of(token)
      assert_includes Admin::EditorScreen::HeldFields.allowed_actions, action, "the frozen form kept #{token}, which the server's allow-list refuses"
    end
  end

  test "bulk translate and per-field translate skip a frozen form" do
    with_locales(%w[en de], default: "en")
    GatedProvider.install!
    site_settings(:default).update!(ai_provider: GatedProvider::NAME, ai_api_key: "sk-test")
    with_test_types do
      about = create_page(title: "About", published: false)
      quote = ContentBlocks::Save.call(ContentBlock.new(owner: about), attributes: { block_type: "test/quote" },
        translations: { "en" => { settings: { "text" => "To be" } } }).record
      visit "/cs-studio/pages/#{about.id}?locale=de"
      await_notes_live
      assert_selector "button", text: /Suggest translations for \d+ empty fields?/
      before = find("button", text: /Suggest translations for \d+ empty fields?/).text[/\d+/].to_i
      assert_operator before, :>=, 2, "the page's title and the quote's text are both empty in German"

      # A first change (a character typed and taken back, so the German text is
      # empty again) is refused as a tie: the quote's form is frozen while its German text is empty.
      record_requests
      delay_next("POST", CLAIM)
      find("#block-#{quote.id}-text").send_keys("x", :backspace)
      await_delayed
      Editing::Reservation.claim(subject: quote, record: about, user: @dana, tab: "tab-dddddddd")
      send_delayed
      assert_selector "#content_block_#{quote.id} [role=alert]", wait: LIVE

      assert_selector "button", text: "Suggest translations for #{before - 1} empty #{before - 1 == 1 ? "field" : "fields"}"
      frozen_translate = "#content_block_#{quote.id} [data-translate-slot='text'] button"
      assert page.all(frozen_translate, minimum: 1).all? { |button| button.disabled? }, "the frozen form's per-field Translate button is dead"
      page.execute_script("document.querySelector(#{frozen_translate.to_json}).click()")
      await_frames
      assert_no_selector "#translation-suggestion-block-#{quote.id}-text [data-translation-suggestion]"

      press "Suggest translations for #{before - 1} empty #{before - 1 == 1 ? "field" : "fields"}"
      assert_text "#{before - 1} #{before - 1 == 1 ? "suggestion" : "suggestions"} ready"
      assert_no_selector "#translation-suggestion-block-#{quote.id}-text [data-translation-suggestion]"
      assert_equal (before - 1), page.all("[data-translation-suggestion]").size
    end
  ensure
    GatedProvider.uninstall!
  end

  SAMPLE_FORM = <<~HTML.freeze
    <form><fieldset>
      <input type="text" name="a" value="1"><input name="b"><input type="TEXT" name="c"><input type="search"><input type="number"><input type="date">
      <input type="checkbox"><input type="radio"><input type="file"><input type="range"><input type="color"><input type="button"><input type="submit"><input type="made-up">
      <input type="hidden" name="h" value="x"><textarea name="t">t</textarea><select><option>1</option></select>
      <button type="button" data-action="click->admin--editor--blocks#move">b</button>
      <div data-action="input->admin--editor--slug-preview#update click->admin--editor--blocks#move">d</div>
      <div data-action="keydown.enter:stop->admin--ui--menu#close admin--ui--menu#select:once@window admin--rich-text--editor#containFocus admin--ui--menu#toggle@document"><span>e</span></div>
      <ul data-action="click->admin--ui--menu#select"><li>x</li></ul>
    </fieldset></form>
  HTML

  # What a control is, for comparing two renderings of one form: its tag, its
  # type, whether it is read-only or disabled and which actions it still has.
  def signature_of(nodes)
    nodes.reject { |node| node.key?("data-held-guard") }.map do |node|
      [ node.name, node["type"], node.key?("readonly"), node.key?("disabled"), node["data-action"] ]
    end
  end

  test "a form frozen in the browser is the form the server renders read-only: the same controls, the same attributes, the same actions, from one list" do
    open_page
    server = Nokogiri::HTML5.fragment(Admin::EditorScreen::HeldFields.call(SAMPLE_FORM)).css("input, textarea, select, button, div, ul")
    page.evaluate_async_script(<<~JS, SAMPLE_FORM)
      const [ html, done ] = [ arguments[0], arguments[arguments.length - 1] ]
      const region = document.getElementById("editing")
      const rules = JSON.parse(region.getAttribute("data-admin--editing--hold-rules-value"))
      import("editing/freeze").then(({ freeze }) => {
        const holder = document.createElement("div")
        holder.id = "sample"
        holder.innerHTML = html
        document.body.append(holder)
        freeze(holder.querySelector("form"), { rules })
        // Without `rules`: the page's own, the same freeze.
        const second = holder.cloneNode(true)
        second.id = "sample-default"
        document.body.append(second)
        freeze(second.querySelector("form"))
        done(true)
      })
    JS
    browser = Nokogiri::HTML5.fragment(page.evaluate_script("document.getElementById('sample').innerHTML")).css("input, textarea, select, button, div, ul")

    assert_equal signature_of(server), signature_of(browser)
    by_default = Nokogiri::HTML5.fragment(page.evaluate_script("document.getElementById('sample-default').innerHTML")).css("input, textarea, select, button, div, ul")
    assert_equal signature_of(server), signature_of(by_default), "freeze(form, { lock }) without rules is the shared rule"
    assert_equal "true", page.evaluate_script("document.querySelector('#sample form').dataset.editingFrozen")
    assert page.evaluate_script("document.querySelector('#sample [data-held-guard]').disabled")
  end

  # --- Review Focus 3 and the hidden document ---------------------------------

  test "Discard, and the document hidden before the answer is drawn: the card is the server's once it is seen" do
    lose_a_tie
    assert_selector "#{card(@block)} [data-editing-kind=lost]", wait: LIVE
    page.execute_script(<<~JS)
      document.querySelector(#{"#{card(@block)} [data-editing-kind] button:last-of-type".to_json}).click()
      window.__hidden = true
      Object.defineProperty(document, "hidden", { get: () => window.__hidden, configurable: true })
      Object.defineProperty(document, "visibilityState", { get: () => (window.__hidden ? "hidden" : "visible"), configurable: true })
      document.dispatchEvent(new Event("visibilitychange"))
    JS
    await_frames
    assert_selector "#{card(@block)} .ProseMirror", text: "My words"
    show_document

    assert_selector "#{card(@block)}[data-editing-held=true] [data-editing-kind=held]", text: "Dana Weiss is editing this block", wait: LIVE
    assert_no_text "My words"
  end

  test "Discard pressed while the document is hidden becomes a catch-up, and the card is still the server's once it is seen" do
    lose_a_tie
    assert_selector "#{card(@block)} [data-editing-kind=lost]", wait: LIVE
    hide_document
    page.execute_script("document.querySelector(#{"#{card(@block)} [data-editing-kind] button:last-of-type".to_json}).click()")
    await_frames
    assert_selector "#{card(@block)} .ProseMirror", text: "My words"
    show_document

    assert_selector "#{card(@block)}[data-editing-held=true] [data-editing-kind=held]", text: "Dana Weiss is editing this block", wait: LIVE
    assert_no_text "My words"
  end

  # --- the existing order of things -----------------------------------------

  test "a claim on the wire when the form is closed is answered, and the release follows it" do
    section = add_block(block_type: "section", settings: { "layout" => "two" })
    inside = add_block(section_id: section.id, section_column: 1)
    open_page
    record_requests
    find("#content_block_#{inside.id} .admin-block-tile__face").click
    delay_next("POST", CLAIM)
    type_in(inside, "Quick", within: panel(inside))
    await_delayed
    within(panel(inside)) { click_button "Close" }
    # The claim on the wire HAS THE QUEUE'S TURN (final review I8): the form's
    # save has been handed to the queue and is not sent while the claim is
    # unanswered. Beside the queue, the save would be on the wire by now.
    await_js "#{autosave_js_of(panel(inside), "autosave.busy")} || window.__sent.some((each) => each.startsWith('PATCH'))", wait: LIVE
    await_frames
    assert_equal [], sent, "a save was sent while the claim ahead of it in the queue was unanswered"
    send_delayed
    assert_eventually(wait: LIVE, message: "the block was not released") { sent.grep(%r{/release\z}).any? }
    assert_writes_settled

    claim_at = sent.index { |each| each.end_with?("/claim") }
    assert_operator claim_at, :<, sent.index { |each| each.start_with?("PATCH") }
    assert_operator sent.index { |each| each.start_with?("PATCH") }, :<, sent.index { |each| each.end_with?("/release") }
    assert_not Editing::Reservation.of(inside).exists?
  end

  # --- fix round 1 -------------------------------------------------------------

  # The NEXT request of `verb` whose URL matches `source` is answered by
  # `answer` (a JS expression: a Response, or a promise of one) instead of
  # going out; `window.__real` is the page's own fetch.
  def answer_next(verb, source, answer, times: 1)
    page.execute_script(<<~JS, verb, source, times)
      const [ verb, source, times ] = arguments
      let left = times
      window.__real = window.__real || window.fetch
      const before = window.fetch
      window.fetch = function (input, init = {}) {
        const url = typeof input === "string" ? input : input.url
        const method = String(init.method || "GET").toUpperCase()
        if (left > 0 && method === verb && new RegExp(source).test(url)) {
          left -= 1
          const signal = init.signal
          return (#{answer})
        }
        return before.apply(this, arguments)
      }
    JS
  end

  HANG = 'new Promise((resolve, reject) => { signal && signal.addEventListener("abort", () => reject(new DOMException("aborted", "TimeoutError"))) })'.freeze

  def hold_controller_js(expression)
    page.evaluate_script("(() => { const hold = window.Stimulus.getControllerForElementAndIdentifier(document.getElementById('editing'), 'admin--editing--hold'); return #{expression} })()")
  end

  def section_with_block
    section = add_block(block_type: "section", settings: { "layout" => "two" })
    [ section, add_block(section_id: section.id, section_column: 1) ]
  end

  test "a release waits for the form's follow-up save: the order on the wire is save, save, release, and nothing holds the block afterwards" do
    section, inside = section_with_block
    open_page
    record_requests
    find("#content_block_#{inside.id} .admin-block-tile__face").click
    delay_next("PATCH", "/content_blocks/#{inside.id}")
    type_in(inside, "First", within: panel(inside))
    await_delayed
    type_in(inside, " second", within: panel(inside))
    within(panel(inside)) { click_button "Close" }
    await_frames
    assert_equal [], releases, "the release was sent while a save was still to come"
    send_delayed

    assert_eventually(wait: LIVE, message: "the block was never released") { releases.size == 1 }
    assert_writes_settled
    assert_equal 2, patches.size
    assert_operator sent.rindex(patches.last), :<, sent.index(releases.first), sent.inspect
    assert_not Editing::Reservation.of(inside).exists?
    assert_includes body_of(inside), "First second"
    assert section
  end

  # Final review I4. `release()` takes the subject out of `held` at once and
  # parks it while the form's last save is outstanding; leaving walked only
  # `held`, so that release was never sent and the hold stayed for two minutes
  # with nobody there. Back is a restoration visit: nothing drains before it,
  # so the editor is gone while the save is still on the wire.
  test "a release that was waiting for its form's last save is sent when the editor is left by a Turbo visit, once, and the row is gone" do
    _section, inside = section_with_block
    visit "/cs-studio/posts"
    await_admin_controllers
    page.execute_script("window.Turbo.visit(#{"/cs-studio/pages/#{@page.id}".to_json})")
    assert_selector "#editing"
    await_notes_live
    record_requests
    find("#content_block_#{inside.id} .admin-block-tile__face").click
    delay_next("PATCH", "/content_blocks/#{inside.id}")
    type_in(inside, "On the wire", within: panel(inside))
    await_delayed
    assert held_by(@me, inside)
    within(panel(inside)) { click_button "Close" }
    await_frames
    assert_equal [], releases, "the release did not wait for the save on the wire"

    page.go_back
    assert_no_selector "#editing", wait: LIVE
    assert_equal "/cs-studio/posts", page.current_path
    send_delayed

    assert_eventually(wait: LIVE, message: "the hold whose release was waiting stayed when the editor was left") { !Editing::Reservation.of(inside).exists? }
    assert_writes_settled
    assert_equal 1, releases.size, sent.inspect
    assert_operator sent.index(patches.last), :<, sent.index(releases.first), sent.inspect
    assert_includes body_of(inside), "On the wire"
  end

  # The same at `pagehide`, where nothing can wait for a queue. A real unload
  # with a save on the wire raises the browser's own dialog, which the driver
  # cannot answer reliably, so the event is dispatched (as
  # `autosave_unload_test.rb` does for `beforeunload`). The page lives on here,
  # which is what shows that the parked release is not sent a second time.
  test "a release that was waiting for its form's last save is sent at pagehide, once, and the row is gone" do
    _section, inside = section_with_block
    open_page
    record_requests
    find("#content_block_#{inside.id} .admin-block-tile__face").click
    delay_next("PATCH", "/content_blocks/#{inside.id}")
    type_in(inside, "On the wire", within: panel(inside))
    await_delayed
    assert held_by(@me, inside)
    within(panel(inside)) { click_button "Close" }
    await_frames
    assert_equal [], releases, "the release did not wait for the save on the wire"

    page.execute_script("window.dispatchEvent(new Event('pagehide'))")
    assert_eventually(wait: LIVE, message: "the hold whose release was waiting stayed at pagehide") { !Editing::Reservation.of(inside).exists? }
    assert_equal 1, releases.size, sent.inspect
    assert_equal 0, hold_controller_js("hold.releasing.size + hold.held.size")
  end

  # Final review I9: this typed fourteen keys 150 ms apart against a hold
  # shortened to a second and asserted that nothing had been saved inside a
  # one-second debounce, so one stalled round failed it. Now no pause can save
  # (the form's debounce is out of reach) and "half a hold later" is the
  # script's clock put back (`age_claim`); every step waits on a condition.
  test "typing for longer than half a hold without a pause renews the hold: one renewal per half hold, and it never lapses" do
    open_page
    record_requests
    raise_debounce(card(@block))
    editor = find("#{card(@block)} .ProseMirror")
    editor.click
    editor.send_keys("x")
    await_claims(1)
    claimed_at = Editing::Reservation.of(@block).pick(:changed_at)

    # Within half a hold: typing on claims nothing more.
    3.times { editor.send_keys("x") }
    await_frames
    assert_equal 1, claims.size, "a change within half a hold of the last claim claimed again: #{sent.inspect}"

    # Half a hold later the next change renews, once, however many keys follow.
    age_claim
    3.times { editor.send_keys("x") }
    await_claims(2)
    3.times { editor.send_keys("x") }
    await_frames
    assert_equal 2, claims.size, "more than one renewal per half hold: #{sent.inspect}"
    assert_operator Editing::Reservation.of(@block).pick(:changed_at), :>, claimed_at, "the renewal did not move the hold on the server"

    # And again half a hold after that.
    age_claim
    editor.send_keys("x")
    await_claims(3)

    assert_equal [], patches, "no pause, so no save yet"
    assert held_by(@me)
    assert_no_selector "[data-editing-kind=lost]"
  end

  test "a claim that never answers gives up, and the save behind it goes: the subject stays held, to be released" do
    open_page
    record_requests
    region_set("timeout", 500)
    answer_next("POST", CLAIM, HANG)
    type_in(@block, "Saved anyway")

    assert_eventually(wait: LIVE, message: "the save behind a claim that never answered was never sent") { patches.size == 1 }
    assert_writes_settled
    assert_includes body_of(@block), "Saved anyway"
    assert_equal 0, hold_controller_js("hold.held.get('block-#{@block.id}')")
  end

  test "a claim answered with a 500 is not a refusal: held with time 0, claimed again on the next change, and released on close" do
    open_page
    record_requests
    answer_next("POST", CLAIM, 'Promise.resolve(new Response("", { status: 500 }))')
    type_in(@block, "O")
    assert_writes_settled
    assert_equal 0, hold_controller_js("hold.held.get('block-#{@block.id}')")
    assert_no_selector "[data-editing-kind=lost]"

    type_in(@block, "n")
    assert_writes_settled
    assert_equal 1, claims.size, "the next change claims again (the first, answered by the stub, never reached the recorder behind it)"
    find("#{card(@block)} [data-action*='admin--editor--blocks#toggle']", match: :first).click
    assert_eventually(wait: LIVE, message: "the block was not released") { releases.size == 1 }
    assert_not Editing::Reservation.of(@block).exists?
  end

  test "a tie on a section's own settings: the notice with Copy and Discard survives the winner's signals and the list merge" do
    section, = section_with_block
    join(:dana, @dana)
    open_page
    delay_next("POST", CLAIM)
    background = "#content_block_#{section.id} select[name='block[settings][background]']"
    find(background).find("option[value=tinted]").select_option
    await_delayed
    using_session(:dana) do
      find(background).find("option[value=tinted]").select_option
      assert_writes_settled
    end
    send_delayed
    assert_selector "#block-#{section.id}-hold [data-editing-kind=lost]", text: "Dana Weiss is editing this block", wait: LIVE

    # The winner's second save is a section's, so its block answers 204 and
    # the LIST is fetched and merged: that merge is what this waits for. (It
    # used to wait for the region to say `answered`, which it had said since
    # its first catch-up, so the two assertions ran before the merge was drawn
    # and guarded nothing: final review I2.)
    page.execute_script("window.__merged = []; document.getElementById('editing').addEventListener('admin--editing--live:merged', (event) => window.__merged.push(event.detail.part))")
    using_session(:dana) do
      find("#content_block_#{section.id} select[name='block[settings][width]']").all("option").last.select_option
      assert_writes_settled
    end
    await_js("window.__merged.includes('blocks')", wait: LIVE)
    await_frames
    assert_selector "#block-#{section.id}-hold [data-editing-kind=lost] button", text: "Copy my text"
    assert_selector "#block-#{section.id}-hold [data-editing-kind=lost] button", text: "Discard"
  end

  test "pause() during a retry's backoff leaves nothing outstanding: the queue is quiet at once" do
    open_page
    answer_next("PATCH", "/content_blocks/#{@block.id}", 'Promise.resolve(new Response("", { status: 500 }))', times: 50)
    type_in(@block, "Failing")
    form = autosave_form(card(@block))
    await_js "(() => { const a = window.Stimulus.getControllerForElementAndIdentifier(document.querySelector(#{form.to_json}), 'admin--saving--autosave'); return Boolean(a.retryTimer) })()"
    page.execute_script("window.Stimulus.getControllerForElementAndIdentifier(document.querySelector(#{form.to_json}), 'admin--saving--autosave').pause()")

    assert_equal false, page.evaluate_script("window.Stimulus.getControllerForElementAndIdentifier(document.querySelector(#{form.to_json}), 'admin--saving--autosave').outstanding()")
    quiet = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      import("saving/queue").then(({ quiet }) => Promise.race([ quiet().then(() => true), new Promise((resolve) => setTimeout(() => resolve(false), 2000)) ])).then(done)
    JS
    assert quiet, "quiet() never resolved: the paused form still counts as outstanding"
  end

  test "Discard on the page settings clears the status line that said the save was refused, and the form is editable again" do
    open_page
    delay_next("POST", CLAIM)
    find("#page-title").send_keys(" 2")
    await_delayed
    Editing::Reservation.claim(subject: @page, record: @page, user: @dana, tab: "tab-dddddddd")
    send_delayed
    assert_selector "#page-hold [data-editing-kind=lost]", wait: LIVE
    assert_selector "#page-save-status", text: /NOT SAVED · DANA WEISS IS EDITING/i
    Editing::Reservation.of(@page).delete_all # version: none (a system test lets the holder go)

    within("#page-hold [data-editing-kind=lost]") { click_button "Discard" }
    assert_no_selector "#page-title[readonly]", wait: LIVE
    assert_selector "#page-save-status", text: "", exact_text: true, wait: LIVE
    assert_selector "#page-settings form[data-controller~='admin--saving--autosave']"
  end

  test "Discard on a post clears the status line that said the save was refused" do
    post = create_post(title: "Hello", published: false)
    visit "/cs-studio/posts/#{post.id}"
    await_notes_live
    delay_next("POST", CLAIM)
    find("input[name='post[title]']").send_keys(" 2")
    await_delayed
    Editing::Reservation.claim(subject: post, record: post, user: @dana, tab: "tab-dddddddd")
    send_delayed
    assert_selector "#editor-notice [data-editing-kind=lost]", wait: LIVE
    assert_selector "#post-save-status", text: /NOT SAVED · DANA WEISS IS EDITING/i
    Editing::Reservation.of(post).delete_all # version: none (a system test lets the holder go)

    within("#editor-notice [data-editing-kind=lost]") { click_button "Discard" }
    assert_no_selector "input[name='post[title]'][readonly]", wait: LIVE
    assert_selector "#post-save-status", text: "", exact_text: true, wait: LIVE
  end

  test "a block deleted by my own other tab: 'You deleted this block in another tab. Your changes weren't saved.'" do
    open_page
    type_unsent(@block, "Unsaved words")
    as(@me, channel: :admin) { ContentBlocks::Destroy.call(@block) }

    assert_selector "#{card(@block)} [role=alert]", text: "You deleted this block in another tab. Your changes weren't saved.", wait: LIVE
  end

  test "a deleted block's notice is read again when the first read fails, and is the plain sentence when no event names it" do
    open_page
    type_unsent(@block, "Unsaved words")
    answer_next("GET", "/editing/page/\\d+/blocks/#{@block.id}\\?*$", 'Promise.resolve(new Response("", { status: 500 }))')
    as(@dana, channel: :admin) { ContentBlocks::Destroy.call(@block) }
    assert_selector "#{card(@block)} [role=alert]", text: "Dana Weiss deleted this block. Your changes weren't saved.", wait: 12

    other = add_block
    visit "/cs-studio/pages/#{@page.id}"
    await_notes_live
    type_unsent(other, "Other words")
    answer_next("GET", "/editing/page/\\d+/blocks/#{other.id}", 'Promise.resolve(new Response("", { status: 404 }))', times: 5)
    as(@dana, channel: :admin) { ContentBlocks::Destroy.call(other) }
    assert_selector "#{card(other)} [role=alert]", text: "This block was deleted. Your changes weren't saved.", wait: LIVE
  end

  test "a lost notice in a hidden section panel opens the panel, and in a collapsed card expands it" do
    section, inside = section_with_block
    open_page
    find("#content_block_#{inside.id} .admin-block-tile__face").click
    delay_next("POST", CLAIM)
    type_in(inside, "Hidden soon", within: panel(inside))
    await_delayed
    within(panel(inside)) { click_button "Close" }
    assert_no_selector panel(inside), wait: 1
    Editing::Reservation.claim(subject: inside, record: @page, user: @dana, tab: "tab-dddddddd")
    send_delayed

    assert_selector "#{panel(inside)} [data-editing-kind=lost]", text: "Dana Weiss is editing this block", wait: LIVE
    assert_selector "#content_block_#{inside.id} .admin-block-tile__face[aria-expanded=true]"
    assert section

    delay_next("POST", CLAIM)
    type_in(@block, "Collapsing")
    await_delayed
    find("#{card(@block)} [data-action*='admin--editor--blocks#toggle']", match: :first).click
    assert_no_selector "#{card(@block)} [data-block-body]:not(.hidden)", wait: 1
    Editing::Reservation.claim(subject: @block, record: @page, user: @dana, tab: "tab-dddddddd")
    send_delayed

    assert_selector "#{card(@block)} [data-editing-kind=lost]", wait: LIVE
    assert_selector "#{card(@block)} [data-block-body]:not(.hidden)"
    assert_selector "#{card(@block)} [data-action*='admin--editor--blocks#toggle'][aria-expanded=true]"
  end

  test "collapsing a section's card releases the holds of the blocks in its panels too" do
    section, inside = section_with_block
    open_page
    find("#content_block_#{inside.id} .admin-block-tile__face").click
    type_in(inside, "In a lane", within: panel(inside))
    assert_writes_settled
    assert held_by(@me, inside)

    find("#content_block_#{section.id} [data-action*='admin--editor--blocks#toggle']", match: :first).click
    assert_eventually(wait: LIVE, message: "the panel's block was not released with its card") { !Editing::Reservation.of(inside).exists? }
  end

  test "collapsing a card sends what the form holds itself, then releases, without a blur" do
    open_page
    record_requests
    type_in(@block, "No blur")
    # A scripted click: no focusout reaches the field before it.
    page.execute_script("document.querySelector(#{"#{card(@block)} [data-action*='admin--editor--blocks#toggle']".to_json}).click()")
    assert_eventually(wait: LIVE, message: -> { "the block was not released: #{sent.inspect} #{hold_controller_js("JSON.stringify({ releasing: hold.releasing.size, held: [...hold.held.keys()], out: hold.formsOf('block-#{@block.id}').map((f) => { const a = window.Stimulus.getControllerForElementAndIdentifier(f, 'admin--saving--autosave'); return [a.timer, a.busy, a.pending] }) })")}" }) { releases.size == 1 }

    assert_includes body_of(@block), "No blur"
    assert_operator sent.index(patches.last), :<, sent.index(releases.last), sent.inspect
    assert_not Editing::Reservation.of(@block).exists?
  end

  test "Discard keeps the notice, and says so, when the card could not be read; the next try draws it" do
    lose_a_tie
    assert_selector "#{card(@block)} [data-editing-kind=lost]", wait: LIVE
    answer_next("GET", "/editing/page/\\d+/blocks/#{@block.id}", 'Promise.resolve(new Response("", { status: 500 }))')
    within("#{card(@block)} [data-editing-kind=lost]") { click_button "Discard" }

    assert_selector "#{card(@block)} [data-editing-kind=lost] [data-editing-copied]", text: "Couldn't load the block. Try again.", wait: LIVE
    assert_selector "#{card(@block)} .ProseMirror", text: "My words"
    within("#{card(@block)} [data-editing-kind=lost]") { click_button "Discard" }
    assert_selector "#{card(@block)}[data-editing-held=true] [data-editing-kind=held]", wait: LIVE
    assert_no_text "My words"
  end

  test "Copy my text does not say Copied when there is nothing to copy" do
    open_page
    delay_next("POST", CLAIM)
    find("#{card(@block)} .ProseMirror").click
    find("#{card(@block)} .ProseMirror").send_keys("x", :backspace)
    await_delayed
    Editing::Reservation.claim(subject: @block, record: @page, user: @dana, tab: "tab-dddddddd")
    send_delayed
    assert_selector "#{card(@block)} [data-editing-kind=lost]", wait: LIVE
    stub_clipboard
    within("#{card(@block)} [data-editing-kind=lost]") { click_button "Copy my text" }

    assert_selector "#{card(@block)} [data-editing-copied]", text: "Couldn't copy. Select the text and copy it yourself.", wait: LIVE
    assert_nil copied
  end

  test "a tie against my own other tab reads 'You're editing this in another tab. Your changes weren't saved.'" do
    open_page
    delay_next("POST", CLAIM)
    type_in(@block, "Mine")
    await_delayed
    using_session(:other) do
      sign_in_via_form(@me)
      visit "/cs-studio/pages/#{@page.id}"
      await_notes_live
      type_in(@block, "Theirs")
      assert_writes_settled
    end
    send_delayed

    assert_selector "#{card(@block)} [role=alert]", text: "You're editing this in another tab. Your changes weren't saved.", wait: LIVE
  end
end
