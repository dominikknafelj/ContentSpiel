require "application_system_test_case"

# The cable connection CS Studio's scripts share (`app/javascript/live/connection.js`),
# imported in the browser from a CS Studio page: the project has no JavaScript
# test runner, and this is a plain module the import map resolves, so a system
# test can call it directly (as `mind_graph_modules_test.rb` does for the mind
# graph's modules).
#
# The page is the Tags screen: `admin--notes--inbox` is on its <body> and listens
# to the person's stream through this same module, and the screen shows no
# record, so the person's subscription is the only one the page itself holds.
# The cable needs no setting up: the suite's `test` adapter delivers to the
# browsers as it is (`notes_live_test.rb`).
class Admin::LiveConnectionSystemTest < ApplicationSystemTestCase
  PERSON = { channel: "Notes::PersonChannel" }.freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    visit admin_tags_path
    await_admin_controllers
  end

  # Calls `script`, a JS function of (the module, the tab's cable consumer,
  # ...args) that may be async, and answers what it returns. A module that
  # does not resolve fails here, with the browser's own sentence.
  def live(script, *args)
    result = page.evaluate_async_script(<<~JS, *args)
      const done = arguments[arguments.length - 1]
      const given = Array.from(arguments).slice(0, -1)
      Promise.all([ import("live/connection"), import("@hotwired/turbo-rails").then((turbo) => turbo.cable.getConsumer()) ])
        .then(async ([ live, consumer ]) => done({ value: await (#{script})(live, consumer, ...given) }))
        .catch((error) => done({ error: String(error) }))
    JS
    assert_nil result["error"], "live/connection could not be used: #{result['error']}"
    result["value"]
  end

  # How many subscriptions the tab's consumer holds whose identifier names `fragment`.
  def subscriptions(fragment)
    live("(live, consumer, fragment) => consumer.subscriptions.subscriptions.filter((each) => each.identifier.includes(fragment)).length", fragment)
  end

  def calls = page.evaluate_script("window.__calls")

  def signal_person = ActionCable.server.broadcast(Notes::Signals.person_stream(users(:one).id), { kind: "inbox" })

  test "two listeners with the same params share one subscription, and stopping one leaves the other" do
    # Every subscription of the page has been answered: a signal sent from
    # here on is received.
    await_notes_live
    assert_equal 1, subscriptions("PersonChannel"), "the page's own listener holds the person's subscription"

    live(<<~JS, PERSON)
      (live, consumer, params) => {
        window.__calls = { a: 0, b: 0 }
        window.__stopA = live.listen(params, () => { window.__calls.a += 1 })
        window.__stopB = live.listen(params, () => { window.__calls.b += 1 })
      }
    JS
    assert_equal 1, subscriptions("PersonChannel"), "two more listeners with the same params made a subscription of their own"

    signal_person
    await_js("window.__calls.a === 1 && window.__calls.b === 1", wait: 8)

    page.execute_script("window.__stopA()")
    signal_person
    await_js("window.__calls.b === 2", wait: 8)
    # Listeners are told one after the other in one task: by the time `b` has
    # heard the second signal, `a` would have too.
    assert_equal({ "a" => 1, "b" => 2 }, calls)
    assert_equal 1, subscriptions("PersonChannel")
  end

  test "the tab's id has the shape the server accepts" do
    tab = live("(live) => live.TAB")

    assert_match Notes::Signals::TAB, tab
    # One id per document: what the page's notes writes send as `X-Notes-Tab`.
    assert_equal tab, page.evaluate_script("document.body.dataset.notesTab")
  end

  test "stopping the last listener ends the subscription" do
    record = { channel: "Notes::RecordChannel", type: "page", id: create_page(title: "Pricing").id.to_s }
    await_notes_live
    assert_equal 0, subscriptions("RecordChannel")

    live(<<~JS, record)
      (live, consumer, params) => {
        window.__told = []
        window.__stop = live.listen(params, Object.assign(() => {}, { connected: () => window.__told.push("connected") }))
      }
    JS
    await_js("window.__told.length === 1", wait: 8)
    assert_equal 1, subscriptions("RecordChannel")
    assert live("(live) => live.connected()"), "a confirmed subscription, and connected() says the socket is down"

    page.execute_script("window.__stop()")
    # Let go a task later (see the module's `pool`), so waited for.
    assert_eventually(message: "the subscription nobody listens to was kept") { subscriptions("RecordChannel").zero? }
    # The socket stays for whoever still listens: the page's own listener.
    assert_equal 1, subscriptions("PersonChannel")
    assert live("(live) => live.connected()")
  end

  # On a subscription the test alone holds: the page's own listener is on the
  # person's, and a `stop` that leaves another listener behind returns before
  # it has anything to let go.
  test "close ends every subscription and the socket and tells the listeners, and a stop that comes later does not touch who listens since" do
    record = { channel: "Notes::RecordChannel", type: "page", id: create_page(title: "Pricing").id.to_s }
    await_notes_live
    live(<<~JS, record)
      (live, consumer, params) => {
        window.__told = []
        window.__stop = live.listen(params, Object.assign(() => {}, { connected: () => window.__told.push("connected"), disconnected: () => window.__told.push("disconnected") }))
      }
    JS
    await_js("window.__told.length === 1", wait: 8)
    live("(live, consumer) => { window.__subscription = consumer.subscriptions.subscriptions.find((each) => each.identifier.includes('RecordChannel')) }")

    live("(live) => live.close()")

    assert_equal 0, live("(live, consumer) => consumer.subscriptions.subscriptions.length")
    assert_eventually(message: "the socket stayed open after close") { live("(live, consumer) => consumer.connection.isActive()") == false }
    assert_not live("(live) => live.connected()")
    # Told, as when the socket drops: the test's listener, and the page's own,
    # which no longer says that every subscription is answered.
    assert_equal %w[connected disconnected], page.evaluate_script("window.__told")
    assert_equal "connecting", page.evaluate_script("document.body.dataset.notesLive")
    assert_equal false, page.evaluate_script("window.__stop.up")
    # An answer of the server's that was still on its way when the entry was
    # closed (here: the subscription's own callbacks, called as Action Cable
    # calls them) reaches nobody.
    page.execute_script("window.__subscription.connected(); window.__subscription.received({ kind: 'threads' }); window.__subscription.disconnected()")
    assert_equal %w[connected disconnected], page.evaluate_script("window.__told")
    assert_equal false, page.evaluate_script("window.__stop.up")

    # Someone listens again, with the same params: a new subscription under
    # the key the closed one had, on a socket opened again for it.
    live(<<~JS, record)
      (live, consumer, params) => {
        window.__again = []
        window.__stopAgain = live.listen(params, Object.assign(() => {}, { connected: () => window.__again.push("connected") }))
      }
    JS
    await_js("window.__again.length === 1", wait: 8)

    # The closed one's `stop`, late. It is the last listener of an entry that
    # is in the pool no more: letting go by its key would take the new
    # subscription out of the pool, find the pool empty and close the socket.
    page.execute_script("window.__stop()")
    await_frames

    assert_equal 1, subscriptions("RecordChannel")
    assert_equal true, live("(live, consumer) => consumer.connection.isActive()"), "the late stop closed the socket under the new listener"
    assert_equal true, page.evaluate_script("window.__stopAgain.up")
    assert live("(live) => live.connected()")
  end

  test "a listener that arrives while the connection is closing keeps the socket, and is answered" do
    record = { channel: "Notes::RecordChannel", type: "page", id: create_page(title: "Pricing").id.to_s }
    await_notes_live

    # In one task: `close` has emptied the pool and waits for the page's own
    # subscription to end; the listener comes in that wait.
    live(<<~JS, record)
      async (live, consumer, params) => {
        window.__told = []
        const closing = live.close()
        window.__stop = live.listen(params, Object.assign(() => {}, { connected: () => window.__told.push("connected") }))
        await closing
      }
    JS

    await_js("window.__told.length === 1", wait: 8)
    assert_equal true, live("(live, consumer) => consumer.connection.isActive()")
    assert_equal 0, subscriptions("PersonChannel")
    assert_equal 1, subscriptions("RecordChannel")
  end

  # A channel action goes out only on a subscription the server has
  # confirmed: Action Cable drops a `perform` on a socket that is not open
  # without a word, and the server raises for a subscription it has not
  # confirmed. The channel is presence's (`Presence::Channel#report`), whose
  # one row says what arrived.
  test "perform sends a channel action while the subscription is up and says so, and sends nothing before it is answered or after it is let go" do
    record = create_page(title: "Pricing")
    params = { channel: "Presence::Channel", type: "page", id: record.id.to_s }
    await_notes_live

    early = live(<<~JS, params)
      (live, consumer, params) => {
        window.__told = []
        window.__stop = live.listen({ ...params, tab: live.TAB }, Object.assign(() => {}, { connected: () => window.__told.push("connected") }))
        return { sent: window.__stop.perform("report", { state: "away" }), up: window.__stop.up, rejected: window.__stop.rejected }
      }
    JS
    assert_equal({ "sent" => false, "up" => false, "rejected" => false }, early)

    await_js("window.__told.length === 1", wait: 8)
    mark = Presence::Mark.find_by!(user: users(:one), record_type: "Page", record_id: record.id)
    assert_equal "here", mark.state, "the action asked for before the subscription was confirmed was sent after all"

    assert_equal true, page.evaluate_script("window.__stop.perform('report', { state: 'away' })")
    assert_eventually(message: "the action never reached the channel") { mark.reload.state == "away" }
    # Without data, as a keep-alive may be sent.
    assert_equal true, page.evaluate_script("window.__stop.perform('beat')")

    # A dropped socket: nothing is sent, and the answer says so.
    page.execute_script("window.__dropped = window.__stop")
    live("(live, consumer) => consumer.subscriptions.subscriptions.find((each) => each.identifier.includes('Presence::Channel')).disconnected()")
    assert_equal false, page.evaluate_script("window.__stop.perform('report', { state: 'here' })")

    page.execute_script("window.__stop()")
    assert_eventually(message: "the subscription nobody listens to was kept") { subscriptions("Presence::Channel").zero? }
    assert_equal false, page.evaluate_script("window.__stop.perform('report', { state: 'here' })")
    assert_eventually(message: "the row of a subscription that ended was kept") { !Presence::Mark.exists?(mark.id) }
  end

  test "a refused subscription says rejected, and performs nothing" do
    await_notes_live

    live(<<~JS)
      (live) => {
        window.__told = []
        window.__stop = live.listen({ channel: "Presence::Channel", type: "page", id: "0", tab: live.TAB }, Object.assign(() => {}, { rejected: () => window.__told.push("rejected") }))
      }
    JS
    await_js("window.__told.length === 1", wait: 8)

    assert_equal({ "up" => false, "settled" => true, "rejected" => true, "sent" => false },
      page.evaluate_script("({ up: window.__stop.up, settled: window.__stop.settled, rejected: window.__stop.rejected, sent: window.__stop.perform('beat') })"))
    assert_equal 0, Presence::Mark.count
  end
end
