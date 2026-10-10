require "application_system_test_case"

# The cable connection CS Studio's scripts share (`app/javascript/live/connection.js`),
# imported in the browser from a CS Studio page: the project has no JavaScript
# test runner, and this is a plain module the import map resolves, so a system
# test can call it directly (as `mind_graph_modules_test.rb` does for the mind
# graph's modules).
#
# The page is the Tags screen: `admin--notes--live` is on its <body> and listens
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

  test "close ends every subscription and the socket, and a listener's later stop does nothing more" do
    await_notes_live
    live("(live, consumer, params) => { window.__stop = live.listen(params, () => {}) }", PERSON)

    live("(live) => live.close()")

    assert_equal 0, live("(live, consumer) => consumer.subscriptions.subscriptions.length")
    assert_eventually(message: "the socket stayed open after close") { live("(live, consumer) => consumer.connection.isActive()") == false }
    assert_not live("(live) => live.connected()")

    page.execute_script("window.__stop()")
    await_frames
    assert_equal 0, live("(live, consumer) => consumer.subscriptions.subscriptions.length")
  end
end
