require "application_system_test_case"

# The merge rule by itself (`app/javascript/notes/merge.js`): "what is read is
# replaced, what is typed is never touched". The module is imported in the
# browser and called directly (the project has no JavaScript test runner; see
# `mind_graph_modules_test.rb`), on an editor whose drawer shows a real thread
# or the list, with the answer the server gives for that view at that moment.
#
# The page's own live controller must not do the merging for the test, so each
# test first ends the tab's cable connection (`quiet`): what someone else
# writes afterwards reaches the page only through the merge the test calls.
# What the controller makes of the module is `notes_live_test.rb` and
# `note_thread_answers_test.rb`.
class Admin::NotesMergeSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    users(:two).update!(name: "Dana")
    @page = create_page(title: "Pricing")
    @thread = as(users(:one)) { Notes::Start.call(@page, body: "My first") }.record
    @first = @thread.first_message
    @second = as(users(:one)) { Notes::Reply.call(@thread, body: "My second") }.record
    sign_in_via_form(users(:one))
  end

  # "Open" is remembered in this browser, and the browser is shared with the
  # tests that follow: every notes system test forgets it again.
  teardown do
    page.execute_script("try { window.localStorage.removeItem('cs-notes-open'); window.sessionStorage.clear() } catch (error) {}")
  end

  def focused?(selector) = page.evaluate_script("document.activeElement === document.querySelector(#{selector.to_json})")

  def open_thread
    visit "/cs-studio/pages/#{@page.id}?notes=open&thread=#{@thread.id}"
    await_notes_live
    assert_selector "#notes-drawer [data-notes-view=thread]"
    assert_eventually(message: "the thread never took the focus") { focused?("#note-thread-#{@thread.id}") }
    quiet
  end

  def open_list
    visit "/cs-studio/pages/#{@page.id}"
    await_notes_live
    find("#notes-open").click
    assert_selector "#notes-drawer #notes-list"
    quiet
  end

  # No signal reaches this tab from here on: its subscriptions and its socket
  # are ended, so the live controller fetches and merges nothing by itself.
  def quiet
    left = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      Promise.all([ import("live/connection"), import("@hotwired/turbo-rails").then((turbo) => turbo.cable.getConsumer()) ])
        .then(async ([ live, consumer ]) => { await live.close(); done(consumer.subscriptions.subscriptions.length) })
    JS
    assert_equal 0, left
  end

  def reply_as_dana(body) = as(users(:two)) { Notes::Reply.call(@thread, body: body) }.tap { |result| assert result.ok?, result.errors.inspect }

  def menu(note, item)
    within("#note-message-#{note.id}") do
      find("button[aria-label='Note actions']").click
      press item
    end
  end

  def field(note) = "#note-message-#{note.id} form[data-note-composer='message-#{note.id}'] textarea[name=body]"

  def reply_field = "#note-thread-#{@thread.id}-reply textarea[name=body]"

  def scroll = page.evaluate_script("(() => { const s = document.querySelector('#notes-drawer [data-note-scroll]'); return { top: s.scrollTop, toBottom: s.scrollHeight - s.scrollTop - s.clientHeight } })()")

  # Fetches the view the drawer's frame shows, the way the live controller
  # does (`fetchPart` and `address`: the frame's own address, a thread
  # without `edit`, `delete` and `shown`, a list with its new-note field's
  # `compose`; the same two headers; the view element of the parsed answer),
  # and hands `script` -- a JS function of (the module, the view on screen,
  # the answer, the page's translator) -- what it needs. Answers what the
  # function returns. A module that does not resolve fails here.
  def merging(script)
    result = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      Promise.all([ import("notes/merge"), import("i18n/messages") ]).then(async ([ merge, { messages } ]) => {
        const frame = document.querySelector("#notes-drawer turbo-frame#notes")
        const view = frame.querySelector(":scope > [data-notes-view]")
        const url = new URL(frame.getAttribute("src"), window.location.origin)
        url.pathname = url.pathname.replace(/\\/threads\\/\\d+$/, "")
        if (view.dataset.notesView === "thread") {
          url.pathname = `${url.pathname}/threads/${encodeURIComponent(view.dataset.noteThread)}`
          ;[ "edit", "delete", "shown" ].forEach((name) => url.searchParams.delete(name))
        } else {
          const subject = view.querySelector(":scope > #notes-new input[name='subject']")?.value
          if (subject && !url.searchParams.has("compose")) url.searchParams.set("compose", subject)
          url.searchParams.delete("notice")
        }
        const response = await fetch(url.pathname + url.search, { headers: { Accept: "text/html", "Turbo-Frame": "notes" } })
        if (!response.ok) throw new Error(`the view's GET answered ${response.status}`)
        const answer = new DOMParser().parseFromString(await response.text(), "text/html").querySelector("turbo-frame#notes > [data-notes-view]")
        const t = (key, values) => messages(document.body).t(key, values)
        done({ value: await (#{script})(merge, view, answer, t) })
      }).catch((error) => done({ error: String(error) }))
    JS
    assert_nil result["error"], "notes/merge could not be used: #{result['error']}"
    result["value"]
  end

  # One merge of the thread on screen with the server's answer for it, as a
  # live refresh makes it. Answers what `mergeThread` returned, as counts.
  def merge_thread
    merging("(merge, view, answer, t) => { const merged = merge.mergeThread(view, answer, { t }); return merged && { gone: merged.gone, kept: merged.kept?.length, arrived: merged.arrived } }")
  end

  def merge_list
    merging("(merge, view, answer) => { const merged = merge.mergeList(view, answer); return merged && { kept: merged.kept.length } }")
  end

  test "a half-typed reply is the same element, with its text, after a merge" do
    open_thread
    find(reply_field).send_keys("Half a thou")
    page.execute_script("window.__field = document.querySelector(#{reply_field.to_json}); window.__messages = document.querySelector('#note-thread-#{@thread.id}-messages')")
    reply_as_dana("Meanwhile")

    merged = merge_thread

    assert_equal({ "gone" => false, "kept" => 0, "arrived" => 1 }, merged)
    # What is read was replaced ...
    assert_selector "#note-thread-#{@thread.id}-messages [data-note-message]", text: "Meanwhile"
    assert_equal false, page.evaluate_script("window.__messages.isConnected"), "the messages part was not drawn again"
    # ... and what is typed is the very element, never out of the page: the
    # focus is still in it.
    assert_equal true, page.evaluate_script("window.__field === document.querySelector(#{reply_field.to_json})")
    assert_equal "Half a thou", find(reply_field).value
    assert focused?(reply_field), "the reply field lost the focus"
  end

  test "a message with an open edit form stays the element it is, and its typed text and baseline stay" do
    open_thread
    menu(@first, "Edit")
    find(field(@first)).send_keys(", changed")
    page.execute_script("window.__message = document.querySelector('#note-message-#{@first.id}'); window.__field = document.querySelector(#{field(@first).to_json}); window.__other = document.querySelector('#note-message-#{@second.id}')")
    reply_as_dana("Meanwhile")

    merged = merge_thread

    assert_equal({ "gone" => false, "kept" => 1, "arrived" => 1 }, merged)
    assert_selector "#note-thread-#{@thread.id}-messages [data-note-message]", text: "Meanwhile"
    assert_equal false, page.evaluate_script("window.__other.isConnected"), "a message nobody is working in was not drawn again"
    assert_equal true, page.evaluate_script("window.__message === document.querySelector('#note-message-#{@first.id}')")
    assert_equal true, page.evaluate_script("window.__field === document.querySelector(#{field(@first).to_json})")
    assert_equal "My first, changed", find(field(@first)).value
    assert_equal "My first", page.evaluate_script("window.__field.defaultValue")
    assert_selector "#note-message-#{@first.id}", count: 1
    assert focused?(field(@first)), "the edit's field lost the focus"
  end

  test "an open delete question stays open" do
    open_thread
    menu(@second, "Delete")
    assert_selector "#note-message-#{@second.id} [data-note-delete-question]"
    page.execute_script("window.__message = document.querySelector('#note-message-#{@second.id}'); window.__question = window.__message.querySelector('[data-note-delete-question]')")
    reply_as_dana("Meanwhile")

    merged = merge_thread

    assert_equal({ "gone" => false, "kept" => 1, "arrived" => 1 }, merged)
    assert_selector "#note-thread-#{@thread.id}-messages [data-note-message]", text: "Meanwhile"
    assert_equal true, page.evaluate_script("window.__message === document.querySelector('#note-message-#{@second.id}')")
    assert_equal true, page.evaluate_script("window.__question === document.querySelector('#note-message-#{@second.id} [data-note-delete-question]')")
    assert_selector "[data-note-delete-question]", count: 1
  end

  # Where the thread's messages stand is read in the same task as the merge,
  # before anything else of the page can run. Read a moment later, a reader at
  # the bottom was found at the bottom even with the merge's own line taken
  # out (seen when this test was written; what else puts them there was not
  # looked for), and that must not pass for the merge's doing.
  test "a message someone else added appears, and the reader's scroll position holds unless they were at the bottom" do
    as(users(:two)) { 2.times { |index| Notes::Reply.call(@thread, body: ([ "A long line #{index}" ] * 40).join("\n")) } }
    open_thread
    measured = <<~JS
      (merge, view, answer, t) => {
        merge.mergeThread(view, answer, { t })
        const scroller = view.querySelector("[data-note-scroll]")
        return { top: scroller.scrollTop, toBottom: scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight }
      }
    JS
    page.execute_script("document.querySelector('#notes-drawer [data-note-scroll]').scrollTop = 40")
    assert_equal 40, scroll["top"]
    assert_operator scroll["toBottom"], :>, 100, "the thread is too short for this test to say anything"
    reply_as_dana("Down here")

    after = merging(measured)

    assert_selector "[data-note-new-divider] + [data-note-message]", text: "Down here", visible: :all
    assert_equal 40, after["top"], "a reader who was not at the bottom was moved"
    # Told instead, in the words the server gave the page.
    assert_selector "#note-thread-#{@thread.id}-reply button[data-note-jump]", text: "1 new message ↓"

    page.execute_script("(() => { const s = document.querySelector('#notes-drawer [data-note-scroll]'); s.scrollTop = s.scrollHeight })()")
    assert_operator scroll["toBottom"], :<, 2
    reply_as_dana("And here")

    after = merging(measured)

    assert_selector "#note-thread-#{@thread.id}-messages [data-note-message]", text: "And here"
    assert_operator after["toBottom"], :<, 2, "a reader at the bottom did not stay there"
    assert_no_selector "button[data-note-jump]"
  end

  test "the list's new-note field is not moved by a merge of the list" do
    open_list
    within("#notes-drawer") { press "New note" }
    find("#notes-new textarea[name=body]").send_keys("Mine, unfinished")
    page.execute_script("window.__field = document.querySelector('#notes-new'); window.__row = document.querySelector('#note-row-#{@thread.id}')")
    other = as(users(:two)) { Notes::Start.call(@page, body: "Started elsewhere") }.record

    merged = merge_list

    assert_equal({ "kept" => 1 }, merged)
    assert_selector "#notes-list a#note-row-#{other.id}", text: "Started elsewhere"
    assert_equal false, page.evaluate_script("window.__row.isConnected"), "a row of the list was not drawn again"
    assert_equal true, page.evaluate_script("window.__field === document.querySelector('#notes-new')")
    assert_equal "Mine, unfinished", find("#notes-new textarea[name=body]").value
    # Never out of the page, not even for a moment: the focus is still in it.
    assert focused?("#notes-new textarea[name=body]"), "the new note's field lost the focus"
    assert_selector "#notes-list #notes-new", count: 1
  end

  test "merging the same answer twice changes nothing the second time" do
    open_thread
    find(reply_field).send_keys("Half a thou")
    reply_as_dana("Meanwhile")

    drawn = merging(<<~JS)
      (merge, view, answer, t) => {
        merge.mergeThread(view, answer, { t })
        const once = view.innerHTML
        merge.mergeThread(view, answer, { t })
        return { once, twice: view.innerHTML }
      }
    JS

    assert_includes drawn["once"], "Meanwhile"
    assert_equal drawn["once"], drawn["twice"]
    assert_equal "Half a thou", find(reply_field).value
  end
end
