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
  # before anything else of the page can run. And every reply is a long one:
  # with more than three messages the older ones are folded away, and a thread
  # of short replies is then too short to scroll at all -- any reader is at
  # the top and at the bottom at once, and both halves of this test would
  # pass with the merge's own line taken out (the second half did, when this
  # test was first written with short replies).
  test "a message someone else added appears, and the reader's scroll position holds unless they were at the bottom" do
    as(users(:two)) { 2.times { |index| Notes::Reply.call(@thread, body: ([ "A long line #{index}" ] * 40).join("\n")) } }
    open_thread
    measured = <<~JS
      (merge, view, answer, t) => {
        merge.mergeThread(view, answer, { t })
        const scroller = view.querySelector("[data-note-scroll]")
        return { top: scroller.scrollTop, toBottom: scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight, room: scroller.scrollHeight - scroller.clientHeight }
      }
    JS
    long = ->(words) { ([ words ] * 40).join("\n") }
    page.execute_script("document.querySelector('#notes-drawer [data-note-scroll]').scrollTop = 40")
    assert_equal 40, scroll["top"]
    assert_operator scroll["toBottom"], :>, 100, "the thread is too short for this test to say anything"
    reply_as_dana(long.call("Down here"))

    after = merging(measured)

    assert_selector "[data-note-new-divider] + [data-note-message]", text: "Down here", visible: :all
    assert_equal 40, after["top"], "a reader who was not at the bottom was moved"
    # Told instead, in the words the server gave the page.
    assert_selector "#note-thread-#{@thread.id}-reply button[data-note-jump]", text: "1 new message ↓"

    page.execute_script("(() => { const s = document.querySelector('#notes-drawer [data-note-scroll]'); s.scrollTop = s.scrollHeight })()")
    assert_operator scroll["toBottom"], :<, 2
    reply_as_dana(long.call("And here"))

    after = merging(measured)

    assert_selector "#note-thread-#{@thread.id}-messages [data-note-message]", text: "And here"
    assert_operator after["room"], :>, 100, "the thread no longer scrolls, so this says nothing"
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

  # With a message being worked in: that is the path where a second merge
  # could do harm (the kept message put into the copy once more, doubled or
  # sent to the end), and markup alone shows neither which element it is nor
  # what its field holds.
  test "merging the same answer twice changes nothing the second time" do
    open_thread
    menu(@first, "Edit")
    find(field(@first)).send_keys(", changed")
    find(reply_field).send_keys("Half a thou")
    page.execute_script("window.__message = document.querySelector('#note-message-#{@first.id}'); window.__field = document.querySelector(#{field(@first).to_json})")
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
    assert_equal true, page.evaluate_script("window.__message === document.querySelector('#note-message-#{@first.id}')")
    assert_equal true, page.evaluate_script("window.__field === document.querySelector(#{field(@first).to_json})")
    assert_selector "#note-message-#{@first.id}", count: 1, visible: :all
    assert_selector "[data-note-message]", text: "Meanwhile", count: 1
    assert_equal "My first, changed", find(field(@first)).value
    assert_equal "My first", page.evaluate_script("window.__field.defaultValue")
    assert_selector "[data-note-new-divider]", count: 1, visible: :all
  end

  # Two refreshes in a row, each with a message from someone else, while an
  # edit is open with the caret in the middle of its text: everything of the
  # edit is what it was after each, and "NEW" stands once, where it first stood.
  test "an open edit is the same element, with its text, baseline, caret and the focus, across two merges that each bring a message" do
    open_thread
    menu(@first, "Edit")
    find(field(@first)).send_keys(", changed")
    page.execute_script("window.__message = document.querySelector('#note-message-#{@first.id}'); window.__field = document.querySelector(#{field(@first).to_json}); window.__field.setSelectionRange(3, 8, 'backward')")
    edit = -> do
      page.evaluate_script(<<~JS)
        ({ message: window.__message === document.querySelector('#note-message-#{@first.id}'), field: window.__field === document.querySelector(#{field(@first).to_json}),
           connected: window.__field.isConnected, value: window.__field.value, baseline: window.__field.defaultValue,
           caret: [ window.__field.selectionStart, window.__field.selectionEnd, window.__field.selectionDirection ], focused: document.activeElement === window.__field,
           copies: document.querySelectorAll('#note-message-#{@first.id}').length, dividers: document.querySelectorAll('[data-note-new-divider]').length,
           marked: document.querySelector('[data-note-new-divider]')?.nextElementSibling?.textContent.includes('One more') })
      JS
    end
    kept = { "message" => true, "field" => true, "connected" => true, "value" => "My first, changed", "baseline" => "My first",
             "caret" => [ 3, 8, "backward" ], "focused" => true, "copies" => 1, "dividers" => 1, "marked" => true }

    reply_as_dana("One more")
    assert_equal({ "gone" => false, "kept" => 1, "arrived" => 1 }, merge_thread)
    assert_equal kept, edit.call

    reply_as_dana("And another")
    assert_equal({ "gone" => false, "kept" => 1, "arrived" => 1 }, merge_thread)
    assert_selector "[data-note-message]", text: "And another", count: 1
    # "NEW" is still above the first of the two.
    assert_equal kept, edit.call
  end

  # The merge moves the messages being worked in into its copy of the answer
  # before the copy takes the old part's place. Whatever can fail must have
  # failed before that: a translator that throws (or one that was not handed
  # over) leaves the view as it was, the edit in the page with its text.
  test "a merge that cannot say NEW fails before it has moved anything: the open edit is where it was" do
    open_thread
    menu(@first, "Edit")
    find(field(@first)).send_keys(", changed")
    page.execute_script("window.__message = document.querySelector('#note-message-#{@first.id}'); window.__field = document.querySelector(#{field(@first).to_json}); window.__messages = document.querySelector('#note-thread-#{@thread.id}-messages')")
    reply_as_dana("Meanwhile")

    [ "{ t: () => { throw new Error('no such message') } }", "{}", "undefined" ].each do |options|
      threw = merging("(merge, view, answer) => { try { merge.mergeThread(view, answer, #{options}); return null } catch (error) { return String(error) } }")

      assert threw, "mergeThread(view, answer, #{options}) did not fail"
      assert_equal true, page.evaluate_script("window.__messages.isConnected && window.__messages === document.querySelector('#note-thread-#{@thread.id}-messages')"), "the messages part was replaced (#{options})"
      assert_equal true, page.evaluate_script("window.__field.isConnected && window.__message === document.querySelector('#note-message-#{@first.id}')"), "the edit left the page (#{options}): #{threw}"
      assert_equal "My first, changed", find(field(@first)).value
      assert_no_selector "[data-note-message]", text: "Meanwhile"
    end

    # And with a translator, the same answer merges.
    assert_equal({ "gone" => false, "kept" => 1, "arrived" => 1 }, merge_thread)
    assert_equal "My first, changed", find(field(@first)).value
  end

  # A second message being worked in, whose reactions in the answer are not
  # what the server draws (an "Add a reaction" with no <summary>): taking
  # them over throws. The reactions of every such message are taken before
  # the first of them is moved, so the throw finds the first edit, and the
  # second, in the page. (One edit is open at a time, so the second is made
  # here by hand, as is the answer's markup.)
  test "reactions that cannot be taken over fail the merge before anything is moved: an edit open on another message is where it was" do
    open_thread
    menu(@first, "Edit")
    find(field(@first)).send_keys(", changed")
    page.execute_script(<<~JS)
      window.__message = document.querySelector('#note-message-#{@first.id}')
      window.__field = document.querySelector(#{field(@first).to_json})
      window.__messages = document.querySelector('#note-thread-#{@thread.id}-messages')
      window.__other = document.querySelector('#note-message-#{@second.id}')
      const form = document.createElement('form')
      form.dataset.noteComposer = 'made-by-hand'
      window.__other.append(form)
    JS
    reply_as_dana("Meanwhile")

    threw = merging(<<~JS)
      (merge, view, answer, t) => {
        const twin = [ ...answer.querySelectorAll('[data-note-message]') ].find((message) => message.dataset.noteMessage === '#{@second.id}')
        twin.querySelectorAll(':scope > [data-note-reactions]').forEach((row) => row.remove())
        const row = document.createElement('div')
        row.dataset.noteReactions = ''
        row.append(Object.assign(document.createElement('details'), { }))
        row.firstElementChild.dataset.reactionAdd = ''
        twin.append(row)
        try { merge.mergeThread(view, answer, { t }); return null } catch (error) { return String(error) }
      }
    JS

    assert threw, "the merge did not fail on reactions it cannot take over"
    assert_equal true, page.evaluate_script("window.__messages.isConnected && window.__messages === document.querySelector('#note-thread-#{@thread.id}-messages')"), "the messages part was replaced"
    assert_equal true, page.evaluate_script("window.__field.isConnected && window.__message === document.querySelector('#note-message-#{@first.id}')"), "the edit left the page: #{threw}"
    assert_equal true, page.evaluate_script("window.__other.isConnected"), "the second message left the page"
    assert_equal "My first, changed", find(field(@first)).value
  end

  # The same for a thread that is gone: the forms of the first rows are taken
  # away only once the line that says why can be written.
  test "a gone thread that cannot be said so keeps its rows and its typed reply" do
    open_thread
    find(reply_field).send_keys("Half a thou")
    forms = page.evaluate_script("document.querySelectorAll('#notes-drawer [data-note-actions] form').length")
    assert_operator forms, :>, 0

    threw = merging("(merge, view) => { try { merge.mergeGone(view, { t: () => { throw new Error('no such message') } }); return null } catch (error) { return String(error) } }")

    assert threw, "mergeGone did not fail"
    assert_equal forms, page.evaluate_script("document.querySelectorAll('#notes-drawer [data-note-actions] form').length")
    assert_no_selector "[data-note-gone]"
    assert_equal "Half a thou", find(reply_field).value

    assert_equal true, merging("(merge, view, answer, t) => merge.mergeGone(view, { t })")
    assert_selector "[data-note-gone]", text: "This thread was deleted"
    assert_equal "Half a thou", find(reply_field).value
  end
end
