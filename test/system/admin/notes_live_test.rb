require "application_system_test_case"

# Live delivery (notes spec §6): a signal over the cable, then a scoped fetch.
# The cable needs nothing set up here: the suite's `test` adapter is the
# in-process `async` adapter with a record of what it sent
# (`ActionCable::SubscriptionAdapter::Test < Async`), and the system test's
# server runs in this process, so a service called from the test thread
# reaches the browsers.
#
# Every assertion that waits for a signal's effect waits `LIVE` seconds: the
# signal is coalesced for half a second before anything is fetched.
class Admin::NotesLiveSystemTest < ApplicationSystemTestCase
  LIVE = 8

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    users(:two).update!(name: "Dana")
    @page = create_page(title: "Pricing")
    @block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    @thread = as(users(:two)) { Notes::Start.call(@block, body: "Is this right?") }.record
    sign_in_via_form(users(:one))
  end

  # "Open" is remembered in this browser, and the browser is shared with the
  # tests that follow: every notes system test forgets it again.
  teardown { page.execute_script("try { window.localStorage.removeItem('cs-notes-open') } catch (error) {}") }

  def open_thread
    visit "/cs-studio/pages/#{@page.id}?notes=open&thread=#{@thread.id}"
    await_notes_live
    assert_selector "#notes-drawer [data-notes-view=thread]"
    # A link with `?notes=open` gives the thread the focus once its frame has
    # loaded (`admin--notes--drawer#loaded`): a test that puts the focus somewhere
    # itself must not do it before that.
    assert_eventually(message: "the thread never took the focus") { focused?("#note-thread-#{@thread.id}") }
  end

  def open_list
    visit "/cs-studio/pages/#{@page.id}"
    await_notes_live
    find("#notes-open").click
    assert_selector "#notes-drawer #notes-list"
  end

  def reply_field = find("#note-thread-#{@thread.id}-reply textarea[name=body]")

  # The reply field as the element it is now, to be asked about later: a
  # field drawn again would get its text back from the draft and could be
  # given the focus again, and would still have lost the caret, the open
  # picker and what was chosen in it.
  def keep_reply_field = page.execute_script("window.__reply = document.querySelector('#note-thread-#{@thread.id}-reply textarea[name=body]')")

  def same_reply_field? = page.evaluate_script("window.__reply.isConnected && window.__reply === document.querySelector('#note-thread-#{@thread.id}-reply textarea[name=body]')")

  def reply_as_dana(body) = as(users(:two)) { Notes::Reply.call(@thread, body: body) }.tap { |result| assert result.ok?, result.errors.inspect }

  def focused?(selector) = page.evaluate_script("document.activeElement === document.querySelector(#{selector.to_json})")

  # Where the open thread's messages are scrolled to: they are the one thing
  # that scrolls under a thread in the drawer (the handoff's decision 35).
  def drawer_scroll = page.evaluate_script("document.querySelector('#notes-drawer [data-note-scroll]').scrollTop")

  # Counts the GETs this tab makes for notes from here on -- a live refresh
  # is one; a note the tab sends is a POST, whose redirect the browser follows
  # by itself -- and keeps the status of the last answer about one delivery.
  def watch_notes_fetches
    page.execute_script(<<~JS)
      window.__notesFetches = 0
      window.__threadFetches = 0
      window.__deliveryStatus = null
      const original = window.fetch
      window.fetch = (...args) => {
        const url = String(args[0].url || args[0])
        const method = String(args[1]?.method || args[0].method || "GET").toUpperCase()
        if (method === "GET" && url.includes("/notes/")) window.__notesFetches += 1
        if (method === "GET" && url.includes("/threads/")) window.__threadFetches += 1
        const answer = original(...args)
        if (url.includes("/notes/deliveries/")) answer.then((response) => { window.__deliveryStatus = response.status })
        return answer
      }
    JS
  end

  # The document as hidden (another tab in front), and seen again: what the
  # page reads, `document.hidden`, and the event that says it changed.
  def hide_document
    page.execute_script(<<~JS)
      window.__hidden = true
      Object.defineProperty(document, "hidden", { get: () => window.__hidden, configurable: true })
      Object.defineProperty(document, "visibilityState", { get: () => (window.__hidden ? "hidden" : "visible"), configurable: true })
      document.dispatchEvent(new Event("visibilitychange"))
    JS
  end

  def show_document = page.execute_script("window.__hidden = false; document.dispatchEvent(new Event('visibilitychange'))")

  # The identifiers the tab's consumer is subscribed to, as [channel, type,
  # id], sorted: one entry per subscription, so a second subscription to the
  # same thing shows.
  def subscriptions
    page.evaluate_script("window.__consumer.subscriptions.subscriptions.map((each) => JSON.parse(each.identifier)).map((id) => [ id.channel, id.type || '', id.id || '' ])").sort_by(&:to_s)
  end

  # The person's subscription as the object it is now, and whether it still
  # is: the document's subscriptions are shared by successive pages, so a
  # visit neither unsubscribes nor subscribes again what both pages hear.
  def keep_person_subscription = page.execute_script("window.__person = window.__consumer.subscriptions.subscriptions.find((each) => each.identifier.includes('PersonChannel'))")

  def same_person_subscription? = page.evaluate_script("window.__consumer.subscriptions.subscriptions.filter((each) => each.identifier.includes('PersonChannel')).every((each) => each === window.__person)")

  def turbo_visit(path)
    page.execute_script("window.__visited = false; document.addEventListener('turbo:load', () => { window.__visited = true }, { once: true }); Turbo.visit(#{path.to_json})")
    await_js("window.__visited === true", wait: LIVE)
  end

  # The tab's cable consumer, where a test can reach it.
  def hold_consumer
    page.execute_script("import('@hotwired/turbo-rails').then((turbo) => turbo.cable.getConsumer()).then((consumer) => { window.__consumer = consumer })")
    await_js("Boolean(window.__consumer)")
  end

  # --- the person's stream --------------------------------------------------------

  test "a mention by someone in another session reaches the badge, the inbox and a toast without a reload" do
    visit "/cs-studio"
    await_notes_live
    assert_no_selector "#sidebar-badge-dashboard"

    using_session(:dana) do
      sign_in_via_form(users(:two))
      visit "/cs-studio/notes/page/#{@page.id}?compose=Page-#{@page.id}"
      await_admin_controllers
      find("#notes-new textarea[name=body]").send_keys("Look at this, @one")
      assert_selector "#notes-new [role=option]", text: "one@example.com"
      find("#notes-new textarea[name=body]").send_keys(:enter, "please")
      within("#notes-new") { press "Add note" }
      assert_selector "[data-note-thread] [data-note-mention]"
    end

    assert_selector "#sidebar-badge-dashboard", text: "1", wait: LIVE
    assert_selector "turbo-frame#notes-for-you [data-delivery][data-unread]", text: "Dana mentioned you"
    # The existing inverted toast, with an accent dot before the sentence.
    assert_selector "#toasts .admin-toast[data-kind=undo]", text: "Dana mentioned you on Pricing"
    assert_selector "#toasts .admin-toast > span[aria-hidden=true][class~='bg-accent']:first-child"
    within("#toasts .admin-toast") { press "Open" }
    # A whole editor visit and then the drawer's frame: more than the default wait on a busy machine.
    assert_selector "#notes-drawer [data-notes-view=thread]", text: "Look at this", wait: LIVE
    assert_current_path(/\/pages\/#{@page.id}\?notes=open&thread=\d+\z/)
  end

  # The signal says nothing and may reach someone who has since lost the right
  # to read the record: the tab asks for the delivery, is refused, and says
  # nothing. (The row is still theirs; it is only hidden.)
  test "a delivery on a record the person can no longer read raises no toast" do
    hidden = as(users(:two)) { Notes::Start.call(create_page(title: "Secret plans"), body: "For @[#{users(:one).id}]") }.record
    hidden.container.update!(trashed_at: Time.current)
    visit "/cs-studio"
    await_notes_live
    watch_notes_fetches

    Notes::Signals.delivery(Notes::Delivery.find_by!(user: users(:one), thread: hidden))

    await_js("window.__deliveryStatus === 404", wait: LIVE)
    await_frames
    assert_no_selector "#toasts .admin-toast"
    assert_no_selector "#sidebar-badge-dashboard"
    assert_no_text "Secret plans"
  end

  test "deliveries read elsewhere take the badge and the card's unread rows with them, and nothing is said" do
    as(users(:two)) { Notes::Start.call(@page, body: "For @[#{users(:one).id}]") }
    visit "/cs-studio"
    await_notes_live
    assert_selector "#sidebar-badge-dashboard", text: "1"
    assert_selector "turbo-frame#notes-for-you [data-delivery][data-unread]"

    as(users(:one)) { assert Notes::MarkRead.call.ok? }

    assert_no_selector "#sidebar-badge-dashboard", wait: LIVE
    assert_no_selector "turbo-frame#notes-for-you [data-delivery][data-unread]"
    assert_selector "turbo-frame#notes-for-you [data-delivery]"
    assert_no_selector "#toasts .admin-toast"
  end

  # --- an open thread ---------------------------------------------------------------

  test "a reply arrives in the open thread under a NEW divider while a half-typed reply is kept" do
    open_thread
    reply_field.send_keys("Half a thou")
    keep_reply_field

    page.execute_script("document.addEventListener('admin--notes--inbox:delivery', (event) => { window.__delivery = event.detail })")

    # Addressed to the viewer, so that there IS a delivery the lines at the
    # end are about: without the mention this person, who never wrote in the
    # thread, would be told nothing and they would pass with nothing tested.
    reply_as_dana("One more thing, @[#{users(:one).id}]")

    assert_selector "#note-thread-#{@thread.id}-messages [data-note-new-divider] + [data-note-message]", text: "One more thing", wait: LIVE
    assert_selector "[data-note-new-divider]", text: /new/i, count: 1
    assert_equal "Half a thou", reply_field.value
    assert same_reply_field?, "the reply field was drawn again"
    assert focused?("#note-thread-#{@thread.id}-reply textarea[name=body]"), "the reply field lost the focus"
    assert_eventually(message: "the delivery was not marked read") { Notes::Delivery.where(user: users(:one)).pluck(:read_at).then { |read| read.any? && read.all? } }
    # The thread is open in this tab, which is visible and focused: the
    # delivery is announced as shown (what `admin--notes--alert` hears), no
    # toast is raised, and the delivery is read -- the badge does not stay up.
    await_js("Boolean(window.__delivery)", wait: LIVE)
    delivery = Notes::Delivery.find_by!(user: users(:one))
    assert_equal({ "id" => delivery.id, "reason" => "mention", "sentence" => "Dana mentioned you", "title" => "Pricing", "excerpt" => "One more thing, @one",
      "url" => "/cs-studio/pages/#{@page.id}?notes=open&thread=#{@thread.id}", "threadId" => @thread.id, "shown" => true, "burstMs" => 10_000 }, page.evaluate_script("window.__delivery"))
    await_frames
    assert_no_selector "#toasts .admin-toast"
    assert_no_selector "#sidebar-badge-dashboard", wait: LIVE

    # A second reply: the divider stays above the first that arrived.
    reply_as_dana("And another")
    assert_selector "#note-thread-#{@thread.id}-messages [data-note-message]", text: "And another", wait: LIVE
    assert_selector "[data-note-new-divider]", count: 1
    assert_selector "[data-note-new-divider] + [data-note-message]", text: "One more thing"
    assert_equal "Half a thou", reply_field.value
  end

  # "Looking at the thread" is one rule: it is open in this tab and the
  # document is not hidden. The window's focus is not asked for, so two
  # windows side by side both stay live.
  test "a window that shows the thread without having the focus is refreshed like any other, with no toast" do
    open_thread
    page.execute_script("document.hasFocus = () => false")
    page.execute_script("document.addEventListener('admin--notes--inbox:delivery', (event) => { window.__shown = event.detail.shown })")

    reply_as_dana("Are you there, @[#{users(:one).id}]?")

    assert_selector "#note-thread-#{@thread.id}-messages [data-note-new-divider] + [data-note-message]", text: "Are you there", wait: LIVE
    await_js("window.__shown === true", wait: LIVE)
    await_frames
    assert_no_selector "#toasts .admin-toast"
    assert_eventually(message: "the delivery was not marked read") { Notes::Delivery.where(user: users(:one)).pluck(:read_at).all? }
  end

  # A hidden document (another tab in front, a minimised window): fetching the
  # thread would read the note on the person's behalf. The counts and the
  # toast only; the thread, and with it the read mark, when it is seen again.
  test "a thread open in a hidden document is not fetched: the note stays unread and is told, and is read when the page is seen again" do
    open_thread
    hide_document
    watch_notes_fetches
    page.execute_script("document.addEventListener('admin--notes--inbox:delivery', (event) => { window.__shown = event.detail.shown })")

    reply_as_dana("While you were away, @[#{users(:one).id}]")

    assert_selector "#toasts .admin-toast", text: "Dana mentioned you on Pricing", wait: LIVE
    assert_equal false, page.evaluate_script("window.__shown")
    assert_selector "#sidebar-badge-dashboard", text: "1", wait: LIVE
    # Every fetch the signals led to has been made (the delivery's is the
    # last of them), and none was the thread's.
    await_js("window.__deliveryStatus === 200", wait: LIVE)
    assert_equal 0, page.evaluate_script("window.__threadFetches")
    assert_no_selector "#note-thread-#{@thread.id}-messages [data-note-message]", text: "While you were away"
    assert_equal [ nil ], Notes::Delivery.where(user: users(:one)).pluck(:read_at)

    # A second signal while hidden changes nothing about that.
    reply_as_dana("Still away?")
    assert_selector "#notes-open-count", text: "1"
    sleep 0.8 # sleep: the coalescing window (500 ms) must have passed before "the thread was not fetched" means anything
    assert_equal 0, page.evaluate_script("window.__threadFetches")

    show_document

    assert_selector "#note-thread-#{@thread.id}-messages [data-note-new-divider] + [data-note-message]", text: "While you were away", wait: LIVE
    assert_selector "#note-thread-#{@thread.id}-messages [data-note-message]", text: "Still away?"
    assert_eventually(message: "the delivery was not marked read") { Notes::Delivery.where(user: users(:one)).pluck(:read_at).all? }
    assert_no_selector "#sidebar-badge-dashboard", wait: LIVE
    assert_equal 1, page.evaluate_script("window.__threadFetches")
  end

  # The reader stands at 40, neither the top nor the bottom: at 0 a scroller
  # that was replaced and never put back would pass for one that was kept.
  # And where they stand is also noted in the very turn of the refresh (an
  # observer of the view's own parts, which runs as the redraw ends), so
  # nothing that scrolls the thread a moment later can pass for the refresh.
  test "a reader who is not at the bottom is not moved: a button says what arrived and leads there" do
    as(users(:two)) { 2.times { |index| Notes::Reply.call(@thread, body: ([ "A long line #{index}" ] * 40).join("\n")) } }
    open_thread
    page.execute_script("document.querySelector('#notes-drawer [data-note-scroll]').scrollTop = 40")
    assert_equal 40, drawer_scroll
    room = page.evaluate_script("(() => { const s = document.querySelector('#notes-drawer [data-note-scroll]'); return s.scrollHeight - s.scrollTop - s.clientHeight })()")
    assert_operator room, :>, 100, "the thread is too short for this test to say anything"
    page.execute_script(<<~JS)
      window.__tops = []
      new MutationObserver(() => window.__tops.push(document.querySelector('#notes-drawer [data-note-scroll]').scrollTop))
        .observe(document.querySelector('#notes-drawer [data-notes-view=thread]'), { childList: true })
    JS

    # Long ones: with more than three messages the older ones are folded
    # away, and a thread of short replies would then be too short to scroll,
    # which puts any reader at 0.
    reply_as_dana(([ "Down here" ] * 40).join("\n"))

    assert_selector "#note-thread-#{@thread.id}-reply button[data-note-jump]", text: "1 new message ↓", wait: LIVE
    assert_equal 40, drawer_scroll
    assert_equal [ 40 ], page.evaluate_script("window.__tops").uniq, "the reader was moved while the thread was drawn again"
    assert_selector "[data-note-new-divider] + [data-note-message]", text: "Down here", visible: :all
    # 12px above the reply field's dock, which is fixed at the bottom.
    gap = page.evaluate_script("document.querySelector('#note-thread-#{@thread.id}-reply').getBoundingClientRect().top - document.querySelector('[data-note-jump]').getBoundingClientRect().bottom")
    assert_in_delta 12, gap, 0.5

    reply_as_dana(([ "And here" ] * 40).join("\n"))
    assert_selector "button[data-note-jump]", text: "2 new messages ↓", count: 1, wait: LIVE
    assert_equal 40, drawer_scroll
    assert_equal [ 40 ], page.evaluate_script("window.__tops").uniq
    assert_operator page.evaluate_script("window.__tops.length"), :>=, 2, "the observer saw no second redraw"
    assert_selector "[data-note-new-divider]", count: 1

    find("button[data-note-jump]").click
    assert_no_selector "button[data-note-jump]"
    at_bottom = page.evaluate_script("(() => { const s = document.querySelector('#notes-drawer [data-note-scroll]'); return s.scrollHeight - s.scrollTop - s.clientHeight < 2 })()")
    assert at_bottom, "the button did not lead to the bottom"
    assert_equal true, page.evaluate_script("document.activeElement.closest('#notes-drawer') !== null"), "the focus left the drawer with the button"
  end

  # Back, Close, Notify and Pin are inside the part a refresh draws again.
  test "a control of the thread's first rows that has the focus has it after a refresh" do
    open_thread
    controls = {
      "a[data-note-back]" => "document.activeElement.matches('a[data-note-back]')",
      "button[data-note-close]" => "document.activeElement.matches('button[data-note-close]')",
      "[data-note-actions] form[action*='follow'] button" => "/follow/.test(document.activeElement.form?.action || '')",
      "[data-note-actions] form[action$='/pin'] button" => "/\\/pin$/.test(document.activeElement.form?.action || '')"
    }

    controls.each_with_index do |(selector, same), index|
      page.execute_script("window.__held = document.querySelector(#{selector.to_json}); window.__held.focus()")
      reply_as_dana("Reply #{index}")

      assert_selector "#note-thread-#{@thread.id}-messages [data-note-message]", text: "Reply #{index}", wait: LIVE
      assert_equal false, page.evaluate_script("window.__held.isConnected"), "#{selector} was not drawn again"
      assert_equal true, page.evaluate_script(same), "#{selector} lost the focus to #{page.evaluate_script('document.activeElement.outerHTML.slice(0, 120)')}"
    end
  end

  test "a message being edited, and one being asked about, stay as they are while the thread around them is refreshed" do
    edited, asked = as(users(:one)) { [ "My first", "My second" ].map { |body| Notes::Reply.call(@thread, body: body).record } }
    open_thread
    within("#note-message-#{edited.id}") do
      find("button[aria-label='Note actions']").click
      press "Edit"
    end
    field = "#note-message-#{edited.id} form[data-note-composer='message-#{edited.id}'] textarea[name=body]"
    find(field).send_keys(", changed")

    reply_as_dana("Meanwhile")

    assert_selector "#note-thread-#{@thread.id}-messages [data-note-message]", text: "Meanwhile", wait: LIVE
    assert_equal "My first, changed", find(field).value
    assert focused?(field), "the edit field lost the focus"
    within("#note-message-#{edited.id}") { press "Save" }
    # Saved, it is one of the folded messages again (four in the thread now).
    assert_selector "#note-message-#{edited.id}", text: "My first, changed", visible: :all
    assert_equal "My first, changed", edited.reload.body

    within("#note-message-#{asked.id}") do
      find("button[aria-label='Note actions']").click
      press "Delete"
    end
    assert_selector "#note-message-#{asked.id} [data-note-delete-question]"

    reply_as_dana("And again")

    assert_selector "#note-thread-#{@thread.id}-messages [data-note-message]", text: "And again", wait: LIVE
    assert_selector "#note-message-#{asked.id} [data-note-delete-question]", text: "Delete this note?"
  end

  # The message under an open edit is deleted by someone else: the edit and
  # its text are kept, at the end of the messages -- inside what scrolls, not
  # beside it, where it would stand fixed between the messages and the
  # composer (the handoff's decision 35).
  test "an edit whose message was deleted elsewhere is kept at the end of the messages, inside their scroller" do
    mine = as(users(:one)) { Notes::Reply.call(@thread, body: "Mine").record }
    open_thread
    within("#note-message-#{mine.id}") do
      find("button[aria-label='Note actions']").click
      press "Edit"
    end
    field = "#note-message-#{mine.id} form[data-note-composer='message-#{mine.id}'] textarea[name=body]"
    find(field).send_keys(", changed")

    as(users(:one)) { assert Notes::DeleteMessage.call(mine).ok? }
    reply_as_dana("After the delete")

    assert_selector "#note-thread-#{@thread.id}-messages [data-note-message]", text: "After the delete", wait: LIVE
    assert_equal "Mine, changed", find(field).value
    assert_selector "#note-thread-#{@thread.id}-messages > [data-note-scroll] > #note-message-#{mine.id}:last-child"
    assert_no_selector "#note-thread-#{@thread.id}-messages > [data-note-message]"
  end

  test "a thread resolved elsewhere under a typed reply: the button reads Reopen and works, and the reply is kept" do
    open_thread
    reply_field.send_keys("Before you close this")
    keep_reply_field
    assert_selector "#note-thread-#{@thread.id}-reply button[data-note-state=resolve]", text: "Resolve"

    as(users(:two)) { assert Notes::Resolve.call(@thread).ok? }

    assert_selector "#note-thread-#{@thread.id}-reply button[data-note-state=reopen]", text: "Reopen", wait: LIVE
    assert_no_selector "button[data-note-state=resolve]"
    assert_selector "#note-thread-#{@thread.id}-messages [data-note-badge=resolved]"
    assert_equal "Before you close this", reply_field.value
    assert same_reply_field?, "the reply field was drawn again"
    assert focused?("#note-thread-#{@thread.id}-reply textarea[name=body]"), "the reply field lost the focus"

    within("#note-thread-#{@thread.id}-reply") { press "Reopen" }

    assert_selector "#note-thread-#{@thread.id}-reply button[data-note-state=resolve]"
    assert_not @thread.reload.resolved?
    assert_equal "Before you close this", reply_field.value
  end

  test "a thread deleted under a typed reply keeps the reply and says so" do
    open_thread
    reply_field.send_keys("Still typing")

    as_owner { assert ContentBlocks::Destroy.call(@block).ok? }

    assert_selector "#note-thread-#{@thread.id}-reply [data-note-gone]", text: "This thread was deleted", wait: LIVE
    assert_equal "Still typing", reply_field.value
    # Nothing is left that would send the text to a thread that is not there
    # (each such answer is the list, over the text): typing more does not
    # bring Reply back, and the send key sends nothing.
    assert_no_selector "#note-thread-#{@thread.id} [data-note-message]"
    reply_field.send_keys(" on")
    assert_selector "#note-thread-#{@thread.id}-reply button[type=submit][disabled]", count: 2
    reply_field.send_keys([ :control, :enter ])
    await_frames
    assert_equal "Still typing on", reply_field.value
    assert_no_selector "#note-thread-#{@thread.id} [data-note-actions] form"
    assert_no_selector "#notes-open-count"

    # Back is still there, and leads to the list.
    find("#notes-drawer a[data-note-back]").click
    assert_selector "#notes-drawer #notes-list"
  end

  test "a thread deleted while it is open with nothing typed gives way to the list, which says so" do
    open_thread

    as_owner { assert ContentBlocks::Destroy.call(@block).ok? }

    assert_selector "#notes-drawer #notes-list [role=status]", text: "This note is gone", wait: LIVE
    assert_no_selector "#notes-drawer [data-notes-view=thread]"
    assert_no_selector "#notes-open-count"
  end

  # The frame's address keeps what its last answer was asked with. A refresh
  # must not ask with it again: `notice=gone` would announce "This note is
  # gone" anew with every signal, and `shown=<id>` would open a fold the
  # reader has closed.
  test "a live refresh asks for the view without the notice and the shown message of the answer before it" do
    gone = as(users(:two)) { Notes::Start.call(@page, body: "Going") }.record
    gone_id = gone.id
    gone.destroy!
    visit "/cs-studio/pages/#{@page.id}?notes=open&thread=#{gone_id}"
    await_notes_live
    assert_selector "#notes-drawer #notes-list [role=status]", text: "This note is gone"
    assert_match(/notice=gone/, page.evaluate_script("document.querySelector('#notes-drawer turbo-frame#notes').getAttribute('src')"))
    page.execute_script("window.__asked = []; const original = window.fetch; window.fetch = (...args) => { window.__asked.push(String(args[0].url || args[0])); return original(...args) }")

    as(users(:two)) { assert Notes::Start.call(@page, body: "A new one").ok? }

    assert_selector "#notes-list a[data-note-row]", text: "A new one", wait: LIVE
    assert_no_selector "#notes-drawer #notes-list [role=status]", text: "This note is gone"
    assert_empty page.evaluate_script("window.__asked.filter((url) => /notice=|shown=/.test(url))")

    # And a thread whose address says which message a reaction was given to.
    find("#note-row-#{@thread.id}").click
    assert_selector "#notes-drawer #note-thread-#{@thread.id}"
    within("#note-message-#{@thread.first_message.id}") do
      find("button[aria-label='Note actions']").click
      press "React"
      find("button[aria-label='React with thumbs up']").click
    end
    assert_selector "#note-message-#{@thread.first_message.id} button[data-reaction='👍'][data-mine]"
    assert_eventually { page.evaluate_script("document.querySelector('#notes-drawer turbo-frame#notes').getAttribute('src')").include?("shown=") }
    page.execute_script("window.__asked = []")

    reply_as_dana("After the reaction")

    assert_selector "#note-thread-#{@thread.id}-messages [data-note-message]", text: "After the reaction", wait: LIVE
    assert_equal 1, page.evaluate_script("window.__asked.filter((url) => url.includes('/threads/')).length")
    assert_empty page.evaluate_script("window.__asked.filter((url) => /notice=|shown=/.test(url))")
  end

  # A live GET that left before this tab's own reply was saved and comes back
  # after the reply's answer was drawn holds the OLDER thread. Drawn, it
  # would take the reply off the screen again, and the tab ignores its own
  # signal, so nothing would put it back. It is dropped, and asked for anew.
  test "an older live answer is not drawn over this tab's own newer one" do
    open_thread
    # The next live GET of the thread is answered now and handed over later.
    page.execute_script(<<~JS)
      window.__gets = 0
      const original = window.fetch
      window.fetch = (...args) => {
        const url = String(args[0].url || args[0])
        const method = String(args[1]?.method || args[0].method || "GET").toUpperCase()
        if (method !== "GET" || !url.includes("/threads/")) return original(...args)
        window.__gets += 1
        if (window.__gets > 1) return original(...args)
        const answer = original(...args)
        return new Promise((resolve) => { window.__release = () => resolve(answer) })
      }
    JS
    reply_as_dana("Theirs")
    assert_eventually(wait: LIVE, message: "the live refresh never left") { page.evaluate_script("typeof window.__release === 'function'") }

    reply_field.send_keys("Mine, meanwhile")
    within("#note-thread-#{@thread.id}-reply") { press "Reply" }
    assert_selector "#note-thread-#{@thread.id}-messages [data-note-message]", text: "Mine, meanwhile"
    page.execute_script("window.__release()")

    # The stale answer is dropped and the thread fetched once more.
    assert_eventually(wait: LIVE, message: "the thread was not asked for again") { page.evaluate_script("window.__gets") >= 2 }
    await_frames
    assert_selector "#note-thread-#{@thread.id}-messages [data-note-message]", text: "Mine, meanwhile"
    assert_selector "#note-thread-#{@thread.id}-messages [data-note-message]", text: "Theirs"
  end

  test "the tab that sent a note does not fetch it again, and the page is never refreshed" do
    open_thread
    page.execute_script("window.__stay = true")
    watch_notes_fetches
    reply_field.send_keys("From this tab")
    within("#note-thread-#{@thread.id}-reply") { press "Reply" }
    assert_selector "[data-note-message]", text: "From this tab"
    sleep 0.8 # sleep: the coalescing window (500 ms) must have passed before "nothing was fetched" means anything

    assert_equal 0, page.evaluate_script("window.__notesFetches") # no GET: the answer to the tab's own POST drew the reply
    assert_equal true, page.evaluate_script("window.__stay") # the document was never replaced
    assert_no_selector "[data-note-new-divider]"
    assert_writes_settled
  end

  # --- the list and the counts ------------------------------------------------------

  test "the list and the count markers follow a note started elsewhere, and a new note's typed text is kept" do
    open_list
    within("#notes-drawer") { press "New note" }
    find("#notes-new textarea[name=body]").send_keys("Mine, unfinished")
    page.execute_script("window.__field = document.querySelector('#notes-new')")

    other = as(users(:two)) { Notes::Start.call(@page, body: "Started elsewhere") }.record

    assert_selector "#notes-list a#note-row-#{other.id}", text: "Started elsewhere", wait: LIVE
    assert_selector "#notes-open-count", text: "2"
    assert_equal "Mine, unfinished", find("#notes-new textarea[name=body]").value
    # The very field, not a copy, and never out of the page: the focus is in it.
    assert_equal true, page.evaluate_script("window.__field === document.querySelector('#notes-new')")
    assert focused?("#notes-new textarea[name=body]"), "the new note's field lost the focus"
    assert_selector "#notes-list #notes-new", count: 1
  end

  test "a block deleted elsewhere takes its group out of the open list, and the counts follow" do
    as(users(:two)) { Notes::Start.call(@page, body: "On the page itself") }
    open_list
    assert_selector "#notes-group-ContentBlock-#{@block.id}"
    assert_selector "#notes-open-count", text: "2"

    as_owner { assert ContentBlocks::Destroy.call(@block).ok? }

    assert_no_selector "#notes-group-ContentBlock-#{@block.id}", wait: LIVE
    assert_selector "#notes-list a[data-note-row]", text: "On the page itself", count: 1
    assert_selector "#notes-open-count", text: "1"
  end

  test "a closed drawer still gets its counts; a burst of signals is one fetch" do
    visit "/cs-studio/pages/#{@page.id}"
    await_notes_live
    assert_selector "#notes-open-count", text: "1"
    watch_notes_fetches

    as(users(:two)) { 5.times { |index| Notes::Start.call(@block, body: "Burst #{index}") } }

    assert_selector "#notes-open-count", text: "6", wait: LIVE
    assert_selector "#notes-marker-ContentBlock-#{@block.id} [data-notes-count]", text: "6"
    assert_operator page.evaluate_script("window.__notesFetches"), :<=, 2
  end

  # A closed drawer is told the counts only: fetching a thread would read it
  # for someone who is not looking. What it holds is fetched when it opens.
  test "a drawer closed while its record changed shows the change when it is opened again" do
    open_list
    find("#notes-open").click
    assert_no_selector "#notes-drawer"

    other = as(users(:two)) { Notes::Start.call(@page, body: "While you were away") }.record
    assert_selector "#notes-open-count", text: "2", wait: LIVE

    find("#notes-open").click
    assert_selector "#notes-drawer #notes-list a#note-row-#{other.id}", text: "While you were away", wait: LIVE
  end

  test "the media panel's notes are live too: a reply arrives in the thread open there" do
    asset = create_media_asset
    thread = as(users(:two)) { Notes::Start.call(asset, body: "Too dark") }.record
    visit "/cs-studio/media?selected=#{asset.id}&thread=#{thread.id}"
    await_notes_live
    assert_selector "#media-notes #note-thread-#{thread.id}", text: "Too dark"
    find("#note-thread-#{thread.id}-reply textarea[name=body]").send_keys("I think")

    as(users(:two)) { assert Notes::Reply.call(thread, body: "Lighter now").ok? }

    assert_selector "#media-notes [data-note-new-divider] + [data-note-message]", text: "Lighter now", wait: LIVE
    assert_equal "I think", find("#note-thread-#{thread.id}-reply textarea[name=body]").value
  end

  # --- the socket -------------------------------------------------------------------

  test "after the socket was down, each part is fetched once: what was missed is there" do
    open_list
    hold_consumer
    page.execute_script("window.__consumer.connection.close()")
    await_js("document.body.dataset.notesLive !== 'connected'")

    missed = as(users(:two)) { Notes::Start.call(@page, body: "While offline, @[#{users(:one).id}]") }.record
    page.execute_script("window.__consumer.connection.open()")

    assert_selector "#notes-list a#note-row-#{missed.id}", text: "While offline", wait: LIVE
    assert_selector "#sidebar-badge-dashboard", text: "1", wait: LIVE
    await_js("document.body.dataset.notesLive === 'connected'")
  end

  # `data-notes-live` is what `await_notes_live` waits on, and two controllers
  # hold the subscriptions: the person's is `admin--notes--inbox`'s, a record's
  # is `admin--notes--live`'s (`notes/live_state` puts their words together).
  # A half that is taken for the whole would not fail a test, it would make
  # one lose a signal now and then. Each subscription's own callbacks are
  # called here, as Action Cable calls them, one side at a time.
  test "the page says it is live only while the person's subscription and the record's are both answered, whichever of the two is not" do
    open_list
    hold_consumer
    state = -> { page.evaluate_script("[ document.body.dataset.notesLive, document.body.getAttribute('data-notes-live-person'), document.body.getAttribute('data-notes-live-records') ]") }
    tell = ->(channel, callback) { page.execute_script("window.__consumer.subscriptions.subscriptions.find((each) => each.identifier.includes(#{channel.to_json})).#{callback}()") }
    assert_equal %w[connected answered answered], state.call

    tell.call("PersonChannel", "disconnected")
    assert_equal %w[connecting waiting answered], state.call
    tell.call("PersonChannel", "connected")
    assert_equal %w[connected answered answered], state.call

    tell.call("RecordChannel", "disconnected")
    assert_equal %w[connecting answered waiting], state.call
    tell.call("RecordChannel", "connected")
    assert_equal %w[connected answered answered], state.call

    # And a half that has said nothing yet is not answered: on a <body> where
    # only one controller has spoken, the page is not live on its word.
    said = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      import("notes/live_state").then(({ report }) => {
        const one = document.createElement("body")
        const other = document.createElement("body")
        report(one, "records", true)
        report(other, "person", true)
        const halves = [ one.dataset.notesLive, other.dataset.notesLive ]
        report(one, "person", true)
        report(other, "records", true)
        done([ ...halves, one.dataset.notesLive, other.dataset.notesLive ])
      })
    JS
    assert_equal %w[connecting connecting connected connected], said
  end

  # A session that ended has its socket closed by the server. The consumer
  # tries once more and is refused for good: no loop, and nothing in the
  # console (which would fail this test in its teardown).
  test "a session that ended closes the socket, and the refused reconnect is quiet and final" do
    open_list
    hold_consumer

    Session.where(user: users(:one)).destroy_all

    await_js("document.body.dataset.notesLive !== 'connected'", wait: LIVE)
    await_js("!window.__consumer.connection.isActive()", wait: LIVE)
    page.execute_script("window.__consumer.connection.open()")
    await_js("!window.__consumer.connection.monitor.isRunning()", wait: LIVE)
    await_js("!window.__consumer.connection.isActive()", wait: LIVE)
    assert_equal "connecting", page.evaluate_script("document.body.dataset.notesLive")
    # The page is as it was: nothing was replaced and nothing navigated.
    assert_selector "#notes-drawer #notes-list"
  end

  # --- across pages ------------------------------------------------------------------
  # A Turbo visit replaces <body>, and with it the controller and its record
  # targets, while the document and its one socket live on.

  test "after a Turbo visit to another editor only that record is listened to, once" do
    other = create_page(title: "About")
    visit "/cs-studio/pages/#{@page.id}"
    await_notes_live
    hold_consumer
    keep_person_subscription
    assert_equal [ [ "Notes::PersonChannel", "", "" ], [ "Notes::RecordChannel", "page", @page.id.to_s ] ], subscriptions

    turbo_visit "/cs-studio/pages/#{other.id}"
    assert_selector "h1", text: "About"
    await_notes_live
    assert_equal true, page.evaluate_script("Boolean(window.__consumer)"), "the document was replaced: this was no Turbo visit"
    assert_equal [ [ "Notes::PersonChannel", "", "" ], [ "Notes::RecordChannel", "page", other.id.to_s ] ], subscriptions
    assert same_person_subscription?, "the person's stream was subscribed to again by the new page"
    assert_no_selector "#notes-open-count"
    watch_notes_fetches

    # The page that was left: nothing here hears it. The page that is here: its counts.
    as(users(:two)) { Notes::Start.call(@page, body: "On the page that was left") }
    as(users(:two)) { Notes::Start.call(other, body: "On this page") }

    assert_selector "#notes-open-count", text: "1", wait: LIVE
    sleep 0.8 # sleep: the coalescing window (500 ms) must have passed before "one fetch" means no second one is on its way
    assert_equal 1, page.evaluate_script("window.__notesFetches")
    assert_selector "#notes-open-count", text: "1"
  end

  test "after a visit and Back the first record is listened to again, once, and the second no more" do
    other = create_page(title: "About")
    visit "/cs-studio/pages/#{@page.id}"
    await_notes_live
    hold_consumer
    keep_person_subscription
    turbo_visit "/cs-studio/pages/#{other.id}"
    assert_selector "h1", text: "About"
    await_notes_live

    page.go_back
    assert_selector "h1", text: "Pricing"
    await_notes_live
    assert_equal true, page.evaluate_script("Boolean(window.__consumer)"), "the document was replaced: Back was no Turbo restoration"
    assert_equal [ [ "Notes::PersonChannel", "", "" ], [ "Notes::RecordChannel", "page", @page.id.to_s ] ], subscriptions
    assert same_person_subscription?, "the person's stream was subscribed to again on the way"
    assert_selector "#notes-open-count", text: "1"
    watch_notes_fetches

    as(users(:two)) { Notes::Start.call(other, body: "On the page that was left") }
    as(users(:two)) { Notes::Start.call(@page, body: "On this page") }

    assert_selector "#notes-open-count", text: "2", wait: LIVE
    sleep 0.8 # sleep: the coalescing window (500 ms) must have passed before "one fetch" means no second one is on its way
    assert_equal 1, page.evaluate_script("window.__notesFetches")
  end

  # A signal waits half a second before anything is fetched. A visit inside
  # that window replaces the controller that was waiting: the next page's
  # takes over what it was told. The signal is handed to the subscription by
  # script, in the same task as the visit, so the visit is always inside the
  # window.
  test "a delivery signalled just before a visit raises its toast on the next page" do
    as(users(:two)) { Notes::Start.call(@page, body: "Before you go, @[#{users(:one).id}]") }
    delivery = Notes::Delivery.find_by!(user: users(:one))
    visit "/cs-studio/tags"
    await_notes_live
    hold_consumer
    page.execute_script("document.addEventListener('admin--notes--inbox:delivery', (event) => { window.__announced = (window.__announced || 0) + 1 })")

    page.execute_script(<<~JS)
      window.__visited = false
      document.addEventListener("turbo:load", () => { window.__visited = true }, { once: true })
      const person = window.__consumer.subscriptions.subscriptions.find((each) => each.identifier.includes("PersonChannel"))
      person.received({ kind: "delivery", delivery_id: #{delivery.id}, reason: "mention" })
      Turbo.visit("/cs-studio/posts")
    JS
    await_js("window.__visited === true", wait: LIVE)

    assert_selector "#toasts .admin-toast", text: "Dana mentioned you on Pricing", wait: LIVE
    assert_current_path "/cs-studio/posts"
    assert_equal 1, page.evaluate_script("window.__announced")
  end

  # Holds every request of this page whose address contains `part` until
  # `release_requests`, and counts them (`window.__heldCalls`): a request
  # kept in flight while the test does something else.
  def hold_requests(part)
    page.execute_script(<<~JS, part)
      const part = arguments[0]
      window.__original = window.fetch
      window.__heldCalls = 0
      window.__gate = new Promise((resolve) => { window.__release = resolve })
      window.fetch = (...args) => {
        if (!String(args[0].url || args[0]).includes(part)) return window.__original(...args)
        window.__heldCalls += 1
        return window.__gate.then(() => window.__original(...args))
      }
    JS
  end

  def release_requests = page.execute_script("if (window.__release) window.__release(); if (window.__original) window.fetch = window.__original")

  # Hands the person's subscription a delivery's signal, as the cable would.
  def signal_delivery(*deliveries)
    page.execute_script(<<~JS, deliveries.map(&:id))
      const person = window.__consumer.subscriptions.subscriptions.find((each) => each.identifier.includes("PersonChannel"))
      arguments[0].forEach((id) => person.received({ kind: "delivery", delivery_id: id, reason: "mention" }))
    JS
  end

  def count_announcements = page.execute_script("window.__announced = []; document.addEventListener('admin--notes--inbox:delivery', (event) => { window.__announced.push(event.detail.id) })")

  # The run that answers a signal is already out -- the sidebar's count is
  # being fetched -- when a visit replaces the controller that started it.
  # What it had not announced is the next page's, at once: nothing waits for
  # another signal.
  test "a visit while the inbox is being fetched: the delivery is announced once, on the next page, with no further signal" do
    as(users(:two)) { Notes::Start.call(@page, body: "Before you go, @[#{users(:one).id}]") }
    delivery = Notes::Delivery.find_by!(user: users(:one))
    visit "/cs-studio/tags"
    await_notes_live
    hold_consumer
    count_announcements
    hold_requests("/notes/unread")

    signal_delivery(delivery)
    await_js("window.__heldCalls >= 1", wait: LIVE)
    turbo_visit "/cs-studio/posts"
    await_notes_live
    release_requests

    assert_selector "#toasts .admin-toast", text: "Dana mentioned you on Pricing", count: 1, wait: LIVE
    sleep 0.8 # sleep: the coalescing window (500 ms) must have passed before "once" means no second run is on its way
    assert_equal [ delivery.id ], page.evaluate_script("window.__announced")
    assert_selector "#toasts .admin-toast", count: 1
    assert_current_path "/cs-studio/posts"
  ensure
    release_requests
  end

  # Two deliveries, the first being read when the visit comes: the one in
  # flight is not announced by the page that left, the one behind it is not
  # stranded, and each is announced once.
  test "a visit while the first of two deliveries is being read: both are announced once on the next page" do
    as(users(:two)) { [ "One, @[#{users(:one).id}]", "Two, @[#{users(:one).id}]" ].each { |body| Notes::Start.call(@page, body: body) } }
    deliveries = Notes::Delivery.where(user: users(:one)).order(:id).to_a
    assert_equal 2, deliveries.size
    visit "/cs-studio/tags"
    await_notes_live
    hold_consumer
    count_announcements
    hold_requests("/notes/deliveries/")

    signal_delivery(*deliveries)
    await_js("window.__heldCalls >= 1", wait: LIVE)
    turbo_visit "/cs-studio/posts"
    await_notes_live
    release_requests

    assert_selector "#toasts .admin-toast", text: "Dana mentioned you on Pricing", count: 2, wait: LIVE
    sleep 0.8 # sleep: the coalescing window (500 ms) must have passed before "once each" means no second run is on its way
    assert_equal deliveries.map(&:id), page.evaluate_script("window.__announced").sort
    assert_selector "#toasts .admin-toast", count: 2
  ensure
    release_requests
  end
end
