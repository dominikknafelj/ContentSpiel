require "application_system_test_case"

# The mind graph's own modules (`app/javascript/mind_graph/`), imported in the
# browser from any CS Studio page: the project has no JavaScript test runner,
# and these are plain modules the import map resolves, so a system test can
# call them directly and compare what they return.
class Admin::MindGraphModulesSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    visit admin_tags_path
    await_admin_controllers
  end

  # The pacing (spec §4.2): a small graph UNFOLDS. Each message is one tick of
  # the simulation -- d3 cools from 1 to its `alphaMin` in 300 of them -- and
  # they come a frame apart, so the whole takes seconds, not one slice.
  test "the layout worker starts from its asset URL, and a small graph unfolds one tick per message until it has cooled down" do
    result = using_wait_time(30) do
      page.evaluate_async_script(<<~JS, ActionController::Base.helpers.asset_path("mind_graph/layout_worker.js"), ActionController::Base.helpers.asset_path("d3-force.js"))
        const [workerUrl, d3Url, done] = arguments
        import("mind_graph/layout_client").then(({ createLayout }) => {
          let ticks = 0
          let last = null
          let first = null
          const layout = createLayout({
            workerUrl, d3Url,
            onTick: (positions) => { ticks += 1; first ??= performance.now(); last = Array.from(positions) },
            onSettled: () => { layout.stop(); done({ ticks, last, took: performance.now() - first }) },
            onError: (message) => done({ error: message })
          })
          layout.start([{ id: 1, radius: 8 }, { id: 2, radius: 8 }, { id: "tag-3", radius: 6 }], [{ source: 1, target: 2 }, { source: 2, target: "tag-3" }])
        })
      JS
    end

    assert_nil result["error"]
    assert_in_delta 300, result["ticks"], 5, "one message per tick of the simulation"
    assert_operator result["took"], :>, 2500, "the layout jumped to its end instead of unfolding"
    assert_equal 6, result["last"].size
    assert result["last"].all? { |value| value.is_a?(Numeric) && value.finite? }
    # d3's initial placement is already distinct per node, so only a simulation
    # that ran puts two linked nodes apart by more than their radii (16) and
    # within three times the link's rest distance (90).
    first, second = result["last"].each_slice(2).first(2)
    distance = Math.hypot(first[0] - second[0], first[1] - second[1])
    assert_operator distance, :>, 16, "linked nodes overlap: the simulation never ran"
    assert_operator distance, :<, 270
  end

  # A larger graph does not make anyone watch three hundred frames of it: it
  # is computed in slices, as fast as the machine allows, and only the last
  # stretch (about 600 ms, some 37 ticks) is shown one tick at a time. So far
  # fewer messages than ticks, and still more than a handful.
  test "a larger graph is laid out in slices and only its last stretch is shown tick by tick" do
    result = using_wait_time(30) do
      page.evaluate_async_script(<<~JS, ActionController::Base.helpers.asset_path("mind_graph/layout_worker.js"), ActionController::Base.helpers.asset_path("d3-force.js"))
        const [workerUrl, d3Url, done] = arguments
        import("mind_graph/layout_client").then(({ createLayout }) => {
          const times = []
          const layout = createLayout({
            workerUrl, d3Url,
            onTick: () => times.push(performance.now()),
            onSettled: () => { layout.stop(); done({ ticks: times.length, lastStretch: times.at(-1) - times.at(-30) }) },
            onError: (message) => done({ error: message })
          })
          const nodes = Array.from({ length: 400 }, (_, index) => ({ id: index + 1, radius: 6 }))
          layout.start(nodes, nodes.slice(1).map((node) => ({ source: node.id - 1, target: node.id })))
        })
      JS
    end

    assert_nil result["error"]
    assert_operator result["ticks"], :>=, 37, "the end of the layout was not shown tick by tick"
    # Fewer messages than the 300 ticks d3 needs: how many fewer depends on how
    # many ticks the machine fits into a 12 ms slice, so no tighter bound.
    assert_operator result["ticks"], :<, 300, "a graph over the threshold was shown tick by tick from the start"
    assert_operator result["lastStretch"], :>, 300, "the last ticks did not come a frame apart"
  end

  # Reduced motion (spec §4.2): the page says so with `start`, and the layout
  # arrives ONCE, at rest. A dragged node moves alone -- every other position
  # is what was last shown -- and the drop shows the result in one step.
  test "with reduced motion the layout arrives in one message, a dragged node moves alone, and the drop shows the result at once" do
    result = using_wait_time(30) do
      page.evaluate_async_script(<<~JS, ActionController::Base.helpers.asset_path("mind_graph/layout_worker.js"), ActionController::Base.helpers.asset_path("d3-force.js"))
        const [workerUrl, d3Url, done] = arguments
        import("mind_graph/layout_client").then(({ createLayout }) => {
          const ticks = []
          let settled = 0
          const layout = createLayout({
            workerUrl, d3Url,
            onTick: (positions) => {
              ticks.push(Array.from(positions))
              // The drag's own message: it is not followed by a `settled`.
              if (settled === 1 && ticks.length === 2) layout.drop(1)
            },
            onSettled: () => {
              settled += 1
              if (settled === 1) layout.drag(1, 400, 400)
              else { layout.stop(); done({ ticks }) }
            },
            onError: (message) => done({ error: message })
          })
          layout.start([{ id: 1, radius: 8 }, { id: 2, radius: 8 }, { id: 3, radius: 8 }], [{ source: 1, target: 2 }, { source: 2, target: 3 }], { reducedMotion: true })
        })
      JS
    end

    assert_nil result["error"]
    rest, dragged, dropped = result["ticks"]
    assert_equal 3, result["ticks"].size, "one message for the layout, one for the drag, one for the drop"
    assert_equal [ 400, 400 ], dragged.first(2)
    assert_equal rest.last(4), dragged.last(4), "the neighbours moved before the drop"
    assert_equal [ 400, 400 ], dropped.first(2), "the dropped node did not stay where it was dropped"
    assert_not_equal rest.last(4), dropped.last(4), "the drop did not lay the neighbours out again"
  end

  # Messages are taken strictly in order: `start` awaits the d3 import, and an
  # `add` handled before it had finished would find no simulation and throw.
  test "an add sent in the same tick as start waits for the d3 import instead of failing" do
    result = page.evaluate_async_script(<<~JS, ActionController::Base.helpers.asset_path("mind_graph/layout_worker.js"), ActionController::Base.helpers.asset_path("d3-force.js"))
      const [workerUrl, d3Url, done] = arguments
      import("mind_graph/layout_client").then(({ createLayout }) => {
        let last = null
        const layout = createLayout({
          workerUrl, d3Url,
          onTick: (positions) => { last = Array.from(positions) },
          onSettled: () => { layout.stop(); done({ last }) },
          onError: (message) => done({ error: message })
        })
        layout.start([{ id: 1, radius: 8 }, { id: 2, radius: 8 }, { id: 3, radius: 6 }], [{ source: 1, target: 2 }, { source: 2, target: 3 }], { reducedMotion: true })
        layout.add({ id: 4, radius: 7, x: 30, y: 0 }, [{ source: 1, target: 4 }])
      })
    JS

    assert_nil result["error"]
    assert_equal 8, result["last"].size, "the layout the page heard of as settled holds the added node"
  end

  # Pinning (spec §4.4): a dragged node is held under the pointer, STAYS where
  # it is dropped once the layout has cooled down around it, and only `unpin`
  # gives it back to the forces. The drag keeps the layout warm, so the first
  # `settled` the page hears of is the one after the drop.
  test "a drag sent in the same tick as start holds its node, the drop leaves it there, and unpin lets it go" do
    result = using_wait_time(40) do
      page.evaluate_async_script(<<~JS, ActionController::Base.helpers.asset_path("mind_graph/layout_worker.js"), ActionController::Base.helpers.asset_path("d3-force.js"))
        const [workerUrl, d3Url, done] = arguments
        import("mind_graph/layout_client").then(({ createLayout }) => {
          let ticks = 0
          let last = null
          let held = null
          let dropped = null
          const layout = createLayout({
            workerUrl, d3Url,
            onTick: (positions) => {
              ticks += 1
              last = [positions[0], positions[1]]
              if (ticks === 5) { held = last; layout.drop(1) }
            },
            onSettled: () => {
              if (!dropped) { dropped = last; layout.unpin([1]) }
              else { layout.stop(); done({ held, dropped, freed: last }) }
            },
            onError: (message) => done({ error: message })
          })
          layout.start([{ id: 1, radius: 8 }, { id: 2, radius: 8 }], [{ source: 1, target: 2 }])
          layout.drag(1, 500, -300)
        })
      JS
    end

    assert_nil result["error"]
    assert_in_delta 500, result["held"][0], 0.01
    assert_in_delta(-300, result["held"][1], 0.01)
    assert_in_delta 500, result["dropped"][0], 0.01, "the dropped node sprang back"
    assert_in_delta(-300, result["dropped"][1], 0.01)
    assert_operator Math.hypot(result["freed"][0] - 500, result["freed"][1] + 300), :>, 100, "an unpinned node stayed where it was held"
  end

  # `settled` carries `after`, the number of messages the worker had taken up
  # when it cooled down, and the client believes only the one that answers
  # everything it sent. THE CLIENT'S HALF, with a worker the test plays itself,
  # so every case is made on purpose and none depends on how fast a machine
  # lays three nodes out: a `settled` that is behind what was sent is not
  # passed on, the one that has caught up is, once, and a late or repeated
  # stale one after that is not either.
  test "the layout client passes on only a settled that answers everything it has sent" do
    log = using_wait_time(10) do
      page.evaluate_async_script(<<~JS)
        const done = arguments[arguments.length - 1]
        const Real = window.Worker
        let worker = null
        window.Worker = class { constructor() { worker = this; this.sent = [] } postMessage(message) { this.sent.push(message.type) } terminate() {} }
        import("mind_graph/layout_client").then(({ createLayout }) => {
          const log = []
          const layout = createLayout({ workerUrl: "unused", d3Url: "unused", onTick: () => log.push("tick"), onSettled: () => log.push("called"), onError: (message) => log.push(`error: ${message}`) })
          window.Worker = Real
          const answer = (after) => { log.push(`raw:${after}`); worker.onmessage({ data: { type: "settled", after } }) }
          layout.start([{ id: 1, radius: 8 }], [])
          layout.pin(1)
          answer(1) // the first layout cooled down before the pin was taken up
          answer(2)
          layout.drag(1, 10, 10)
          answer(2) // late, and stale again
          layout.drop(1)
          answer(3) // answers the drag, not yet the drop
          answer(4)
          layout.stop()
          answer(4) // nothing is delivered after stop
          done({ log, sent: worker.sent })
        }).catch((error) => { window.Worker = Real; done({ error: String(error) }) })
      JS
    end

    assert_nil log["error"]
    assert_equal %w[start pin drag drop], log["sent"]
    assert_equal %w[raw:1 raw:2 called raw:2 raw:3 raw:4 called raw:4], log["log"]
  end

  # THE WORKER'S HALF, with the real one: `after` counts the messages taken
  # up. An `unpin` (which warms the layout up again) is sent right behind
  # `start`, and whichever way that race
  # goes on this machine the page hears of ONE settled layout, the unpin's.
  # With reduced motion three nodes usually cool down inside the first 12 ms
  # slice, before the unpin is handled, and the worker then posts `settled`
  # twice (`raw:1`, `raw:2`); on a slower machine the unpin is taken up while
  # the first layout is still running and there is only `raw:2`. (That it is
  # machine speed that decides was found in CI: this test used to insist on
  # `raw:1`. The stale case itself is the test above.) The end of the watch is
  # a message that changes nothing (a drag of a node that isn't there), which
  # the idle worker answers at once: every `settled` before it has arrived by
  # then, so "exactly once" is not a wait.
  test "an unpin sent right behind start is settled once, and only when the layout it warmed up has cooled down" do
    log = settled_log(<<~JS)
      layout.start([{ id: 1, radius: 8 }, { id: 2, radius: 8 }, { id: 3, radius: 6 }], [{ source: 1, target: 2 }, { source: 2, target: 3 }], { reducedMotion: true })
      layout.unpin([1])
      onCall = (count) => { if (count === 1) layout.drag("no such node", 0, 0); else finish() }
    JS

    assert_equal 2, log.count("called"), "one for the unpin's layout, one for the drag that ended the watch: #{log}"
    first = log.index("called")
    assert_equal "raw:2", log[first + 1], "the page was told of a settled that did not answer the unpin: #{log}"
    assert_equal %w[called raw:3], log.last(2), log.inspect
    assert_not_includes log[0...first], "raw:2"
    assert_includes [ [], [ "raw:1" ] ], log[0...first], "something other than the first layout's own settled came before the unpin's: #{log}"
  end

  # Every message is answered, whatever it changes: a drag and its drop
  # together by the one `settled` after the drop, a pin (which moves nothing)
  # at once, an unpin when the layout has cooled down again.
  test "a drag with its drop, a pin and an unpin on a graph at rest are each settled exactly once" do
    log = settled_log(<<~JS)
      layout.start([{ id: 1, radius: 8 }, { id: 2, radius: 8 }], [{ source: 1, target: 2 }], { reducedMotion: true })
      onCall = (count) => {
        if (count === 1) { layout.drag(1, 300, 200); layout.drop(1) }
        else if (count === 2) layout.pin(2)
        else if (count === 3) layout.unpin([1, 2])
        else if (count === 4) layout.drag("no such node", 0, 0)
        else finish()
      }
    JS

    assert_equal 5, log.count("called"), "the first layout, the drag and drop together, the pin, the unpin, and the drag that ended the watch: #{log}"
    calls = log.each_index.select { |index| log[index] == "called" }
    assert_equal %w[raw:1 raw:3 raw:4 raw:5 raw:6], calls.map { |index| log[index + 1] }, log.inspect
  end

  # Mind graph canvas spec §4.4: a pinch zooms towards the point between the
  # two fingers, and moving both pans. Synthetic pointer events on a canvas of
  # the test's own, at the window's top-left corner so client coordinates are
  # canvas coordinates.
  test "input: two pointers pinch -- the change in their distance zooms around their midpoint, the midpoint's movement pans" do
    calls = input_calls(<<~JS)
      fire("pointerdown", 1, 100, 100)
      fire("pointerdown", 2, 200, 100)
      fire("pointermove", 2, 300, 100)
    JS

    assert_equal [ [ "press", 100, 100 ], [ "pan", 50, 0 ], [ "zoom", 200, 100, 2 ] ], calls
  end

  test "input: a two-pointer gesture ends a drag, is never a click, and lifting one finger does not jump" do
    calls = input_calls(<<~JS, target: true)
      fire("pointerdown", 1, 100, 100)
      fire("pointermove", 1, 120, 100)
      fire("pointerdown", 2, 220, 100)
      fire("pointermove", 1, 100, 100)
      fire("pointerup", 2, 220, 100)
      fire("pointermove", 1, 400, 300)
      fire("pointerup", 1, 400, 300)
      fire("pointermove", 1, 50, 50)
    JS

    assert_equal [ [ "press", 100, 100 ], [ "drag", 120, 100 ], [ "drop" ], [ "pan", -10, 0 ], [ "zoom", 160, 100, 1.2 ], [ "hover", 50, 50 ] ], calls
  end

  test "input: one pointer still pans, a press without movement is a click, and a cancelled press is neither" do
    calls = input_calls(<<~JS)
      fire("pointerdown", 1, 10, 10)
      fire("pointermove", 1, 40, 30)
      fire("pointerup", 1, 40, 30)
      fire("pointerdown", 1, 60, 60)
      fire("pointerup", 1, 61, 60)
      fire("pointerdown", 1, 80, 80)
      fire("pointercancel", 1, 80, 80)
    JS

    assert_equal [ [ "press", 10, 10 ], [ "pan", 30, 20 ], [ "press", 60, 60 ], [ "click", 61, 60 ], [ "press", 80, 80 ] ], calls
  end

  # A touch whose `pointerup` and `pointercancel` never reach the canvas still
  # loses its capture, and that ends it -- without a click. Left in the table,
  # it would make the next touch the second finger of a pinch with a ghost.
  test "input: a pointer whose capture is lost is over, without a click, and the next touch is a press of its own" do
    calls = input_calls(<<~JS)
      fire("pointerdown", 1, 100, 100)
      fire("lostpointercapture", 1, 100, 100)
      fire("pointerdown", 2, 200, 100)
      fire("pointermove", 2, 300, 100)
      fire("pointerup", 2, 300, 100)
      fire("pointermove", 2, 50, 50)
    JS

    assert_equal [ [ "press", 100, 100 ], [ "press", 200, 100 ], [ "pan", 100, 0 ], [ "hover", 50, 50 ] ], calls
  end

  # After an ordinary release the browser reports the lost capture too: it
  # finds nothing left to end, so the click is made once and nothing else.
  test "input: the lost capture that follows an ordinary release changes nothing, and a held node is dropped when the capture is lost" do
    calls = input_calls(<<~JS, target: true)
      fire("pointerdown", 1, 60, 60)
      fire("pointerup", 1, 61, 60)
      fire("lostpointercapture", 1, 61, 60)
      fire("pointerdown", 1, 100, 100)
      fire("pointermove", 1, 120, 100)
      fire("lostpointercapture", 1, 120, 100)
    JS

    assert_equal [ [ "press", 60, 60 ], [ "drop" ], [ "click", 61, 60 ], [ "press", 100, 100 ], [ "drag", 120, 100 ], [ "drop" ] ], calls
  end

  # A mouse is the exception: it always produces a `pointerup`, so a capture
  # the browser drops between the press and the first move must not end the
  # drag -- the node would stay where it started under a pointer still held.
  test "input: a mouse that loses its capture keeps its press -- the next move still drags, and the release ends it" do
    calls = input_calls(<<~JS, target: true)
      fire("pointerdown", 1, 100, 100, "mouse")
      fire("lostpointercapture", 1, 100, 100, "mouse")
      fire("pointermove", 1, 140, 130, "mouse")
      fire("pointerup", 1, 140, 130, "mouse")
      fire("pointermove", 1, 50, 50, "mouse")
    JS

    assert_equal [ [ "press", 100, 100 ], [ "drag", 140, 130 ], [ "drop" ], [ "hover", 50, 50 ] ], calls
  end

  # A double click is two clicks, each of them an `onClick`, and then the
  # browser's own `dblclick`, which is what `onDoubleClick` is: the shortcut
  # that releases a pinned node.
  test "input: a double click is reported where it happened, after its two clicks" do
    calls = input_calls(<<~JS, target: true)
      fire("pointerdown", 1, 100, 100, "mouse")
      fire("pointerup", 1, 100, 100, "mouse")
      fire("pointerdown", 1, 101, 100, "mouse")
      fire("pointerup", 1, 101, 100, "mouse")
      doubleClick(101, 100)
    JS

    assert_equal [ [ "press", 100, 100 ], [ "drop" ], [ "click", 100, 100 ], [ "press", 101, 100 ], [ "drop" ], [ "click", 101, 100 ], [ "doubleclick", 101, 100 ] ], calls
  end

  test "a worker that can't load d3-force reports an error instead of hanging" do
    result = page.evaluate_async_script(<<~JS, ActionController::Base.helpers.asset_path("mind_graph/layout_worker.js"))
      const [workerUrl, done] = arguments
      import("mind_graph/layout_client").then(({ createLayout }) => {
        const layout = createLayout({
          workerUrl, d3Url: "/assets/no-such-file.js",
          onTick: () => {}, onSettled: () => done({ settled: true }),
          onError: (message) => { layout.stop(); done({ error: message }) }
        })
        layout.start([{ id: 1, radius: 8 }], [])
      })
    JS

    assert result["error"].present?
  end

  test "camera: graph and screen coordinates convert both ways" do
    assert_equal [ 30, 50 ], js_module("mind_graph/camera", "m.toScreen({ k: 2, tx: 10, ty: 20 }, 10, 15)")
    assert_equal [ 10, 15 ], js_module("mind_graph/camera", "m.toGraph({ k: 2, tx: 10, ty: 20 }, 30, 50)")
  end

  test "camera: zooming keeps the point under the pointer where it is, and stops at the limits" do
    kept = js_module("mind_graph/camera", "(() => { const c = m.zoomAt(m.identity(), 100, 80, 2); return [c.k, ...m.toScreen(c, 100, 80)] })()")
    assert_equal [ 2, 100, 80 ], kept

    assert_equal 4, js_module("mind_graph/camera", "m.zoomAt(m.identity(), 0, 0, 1000).k")
    assert_in_delta 0.05, js_module("mind_graph/camera", "m.zoomAt(m.identity(), 0, 0, 0.000001).k")
  end

  test "camera: panning moves by screen pixels" do
    assert_equal({ "k" => 2, "tx" => 15, "ty" => 17 }, js_module("mind_graph/camera", "m.panBy({ k: 2, tx: 10, ty: 20 }, 5, -3)"))
  end

  test "camera: bounds cover the given nodes only, and are null for none" do
    assert_equal({ "minX" => -10, "minY" => 0, "maxX" => 30, "maxY" => 40 },
      js_module("mind_graph/camera", "m.bounds(new Float32Array([-10, 0, 30, 40, 999, 999]), [0, 1])"))
    assert_nil js_module("mind_graph/camera", "m.bounds(new Float32Array([1, 2]), [])")
  end

  test "camera: fit leaves a tenth of the canvas on each side of a wide box, its middle in the middle" do
    result = js_module("mind_graph/camera", <<~JS)
      (() => {
        const box = { minX: -500, minY: -100, maxX: 500, maxY: 100 }
        const c = m.fit(box, 800, 600)
        return { k: c.k, topLeft: m.toScreen(c, box.minX, box.minY), bottomRight: m.toScreen(c, box.maxX, box.maxY), middle: m.toScreen(c, 0, 0) }
      })()
    JS

    assert_in_delta 0.64, result["k"], 0.001
    assert_in_delta 80, result["topLeft"][0], 0.01
    assert_in_delta 720, result["bottomRight"][0], 0.01
    assert_equal [ 400, 300 ], result["middle"].map(&:round)
    assert_operator result["topLeft"][1], :>=, 60
  end

  # Review focus 5: one node, or all nodes at one point.
  test "camera: fitting a single point does not divide by zero or zoom past 3" do
    result = js_module("mind_graph/camera", "(() => { const c = m.fit({ minX: 7, minY: 7, maxX: 7, maxY: 7 }, 800, 600); return [c.k, ...m.toScreen(c, 7, 7)] })()")

    assert_equal [ 3, 400, 300 ], result
    assert_equal({ "k" => 1, "tx" => 400, "ty" => 300 }, js_module("mind_graph/camera", "m.fit(null, 800, 600)"))
  end

  # Layout points spec, decision 15: a small graph is zoomed in to fill the
  # box, up to 3 and never further.
  test "camera: a small graph is zoomed in to fill the box, up to 3 and never further" do
    small = js_module("mind_graph/camera", "m.fit({ minX: -100, minY: -50, maxX: 100, maxY: 50 }, 800, 600).k")
    tiny = js_module("mind_graph/camera", "m.fit({ minX: -10, minY: -5, maxX: 10, maxY: 5 }, 800, 600).k")

    assert_in_delta 3.2, js_module("mind_graph/camera", "Math.min(800 * 0.8 / 200, 600 * 0.8 / 100)"), 0.001
    assert_equal 3, small, "200 by 100 would fill 80% at 3.2: it stops at the cap"
    assert_equal 3, tiny
    assert_in_delta 2.4, js_module("mind_graph/camera", "m.fit({ minX: -100, minY: -50, maxX: 100, maxY: 50 }, 600, 300).k"), 0.001
  end

  test "hit test: the nearest node within its radius plus slack, or none" do
    hit = ->(sx, sy) do
      js_module("mind_graph/hit_test", "m.nodeAt({ positions: new Float32Array([0, 0, 100, 0, 104, 0]), indexes: [0, 1, 2], radii: [8, 8, 8], camera: { k: 1, tx: 0, ty: 0 }, sx: #{sx}, sy: #{sy} })")
    end

    assert_equal 0, hit.call(3, 3)
    assert_equal 0, hit.call(11, 0), "inside the 4px slack"
    assert_equal(-1, hit.call(13, 0))
    assert_equal 2, hit.call(103, 0), "two overlap: the nearer centre wins"
    assert_equal 1, hit.call(101, 0)
  end

  test "hit test: a hidden node is not hit, and the radius does not grow with zoom" do
    assert_equal(-1, js_module("mind_graph/hit_test", "m.nodeAt({ positions: new Float32Array([0, 0]), indexes: [], radii: [8], camera: { k: 1, tx: 0, ty: 0 }, sx: 0, sy: 0 })"))
    assert_equal(-1, js_module("mind_graph/hit_test", "m.nodeAt({ positions: new Float32Array([0, 0]), indexes: [0], radii: [8], camera: { k: 4, tx: 0, ty: 0 }, sx: 20, sy: 0 })"))
  end

  # The round of 2026-10-08: a dot's target is at least 24 px across on screen,
  # whatever its radius and whatever the zoom.
  test "hit test: a small dot's target is at least 24 pixels across, at any zoom" do
    hit = ->(sx, k) do
      js_module("mind_graph/hit_test", "m.nodeAt({ positions: new Float32Array([0, 0]), indexes: [0], radii: [4.5], camera: { k: #{k}, tx: 0, ty: 0 }, sx: #{sx}, sy: 0 })")
    end

    assert_equal 24, js_module("mind_graph/hit_test", "m.MIN_TARGET")
    [ 0.05, 1, 4 ].each do |k|
      assert_equal 0, hit.call(11.5, k), "11.5 px from a 4.5 px dot at zoom #{k}"
      assert_equal(-1, hit.call(12.5, k), "12.5 px from it at zoom #{k}")
    end
  end

  # Dot and label are one target. The label's box runs from the node's edge
  # (4 px before the text) to the end of the text, 14 px tall, and it counts
  # only when it is among the labels the frame drew.
  test "hit test: a drawn label is part of its node's target, and a label that is not drawn is not" do
    hit = ->(sx, sy, labels: "[{ index: 0, x: 12, y: 0 }, { index: 1, x: 12, y: 100 }]") do
      js_module("mind_graph/hit_test", "m.nodeAt({ positions: new Float32Array([0, 0, 0, 100, 60, 0]), indexes: [0, 1, 2], radii: [8, 8, 8], camera: { k: 1, tx: 0, ty: 0 }, sx: #{sx}, sy: #{sy}, labels: #{labels}, widths: [80, 40, 50] })")
    end

    assert_equal 0, hit.call(30, 0), "on the label's text"
    assert_equal 0, hit.call(92, 6), "its last pixel, near its lower edge"
    assert_equal(-1, hit.call(93, 0), "past the end of the text")
    assert_equal(-1, hit.call(30, 8), "below the label")
    assert_equal 1, hit.call(50, 100), "each label answers for its own node"
    assert_equal(-1, hit.call(54, 100), "past the end of the shorter one")
    assert_equal 2, hit.call(60, 0), "a dot under another node's label wins over the label"
    assert_equal(-1, hit.call(30, 0, labels: "[]"), "a label that is not drawn can't be pressed")
    assert_equal(-1, hit.call(30, 0, labels: "undefined"), "and none is the default")
  end

  # The hovered node's label is drawn last, over the others: where two boxes
  # overlap, the one on top answers.
  test "hit test: of two overlapping labels the one drawn last wins" do
    hit = js_module("mind_graph/hit_test", "m.nodeAt({ positions: new Float32Array([0, 0, 20, 4]), indexes: [0, 1], radii: [6, 6], camera: { k: 1, tx: -500, ty: 0 }, sx: 60, sy: 2, labels: [{ index: 0, x: 40, y: 0 }, { index: 1, x: 50, y: 4, hover: true }], widths: [80, 80] })")

    assert_equal 1, hit
  end

  # Where the card stands (spec §5.3): 22 px right of the node's edge and
  # centred on it; left of it where the right has no room; inside the canvas
  # by 8 px whatever the node does.
  test "card placement: beside the node, 22 pixels from its edge and centred on it" do
    place = js_module("mind_graph/card_placement", "m.placeCard({ x: 300, y: 250, radius: 8, cardWidth: 240, cardHeight: 120, width: 1000, height: 600 })")

    assert_equal({ "left" => 330, "top" => 190, "side" => "right" }, place)
    assert_equal [ 22, 8 ], js_module("mind_graph/card_placement", "[m.GAP, m.MARGIN]")
  end

  test "card placement: it flips to the node's left where the right edge is too near, exactly from the first pixel that does not fit" do
    place = ->(x) { js_module("mind_graph/card_placement", "m.placeCard({ x: #{x}, y: 250, radius: 8, cardWidth: 240, cardHeight: 120, width: 1000, height: 600 })") }

    # Right of the node the card ends at x + 8 + 22 + 240, and may reach 992.
    assert_equal({ "left" => 752, "top" => 190, "side" => "right" }, place.call(722))
    assert_equal({ "left" => 453, "top" => 190, "side" => "left" }, place.call(723))
    assert_equal({ "left" => 660, "top" => 190, "side" => "left" }, place.call(930))
  end

  test "card placement: it is clamped into the canvas near the top, the bottom and where neither side has room" do
    place = ->(arguments) { js_module("mind_graph/card_placement", "m.placeCard({ radius: 8, cardWidth: 240, cardHeight: 120, width: 1000, height: 600, #{arguments} })") }

    assert_equal 8, place.call("x: 300, y: 20")["top"], "near the top it slides down along the node"
    assert_equal 472, place.call("x: 300, y: 590")["top"], "near the bottom it slides up"
    assert_equal({ "left" => 752, "top" => 472 }, place.call("x: 5000, y: 5000").slice("left", "top"), "a node far outside to the right leaves the card in the nearest corner")
    assert_equal({ "left" => 8, "top" => 8 }, place.call("x: -5000, y: -5000").slice("left", "top"), "and one far outside to the left in the opposite one")
    narrow = js_module("mind_graph/card_placement", "m.placeCard({ x: 150, y: 100, radius: 8, cardWidth: 240, cardHeight: 120, width: 300, height: 600 })")
    assert_equal({ "left" => 8, "top" => 40, "side" => "left" }, narrow, "no room on either side: the card shows whole, at the margin, over the node")
    assert_equal({ "left" => 8, "top" => 8 }, js_module("mind_graph/card_placement", "m.placeCard({ x: 150, y: 100, radius: 8, cardWidth: 400, cardHeight: 700, width: 300, height: 600 })").slice("left", "top"), "a card larger than the canvas starts at the margin")
  end

  # A node the layout never placed (the worker failed; the selection came from
  # the list) has no place to stand beside.
  test "card placement: a node without a place gets the card in the canvas's top-right corner" do
    place = js_module("mind_graph/card_placement", "m.placeCard({ x: NaN, y: NaN, radius: 8, cardWidth: 240, cardHeight: 120, width: 1000, height: 600 })")

    assert_equal({ "left" => 752, "top" => 8, "side" => "right" }, place)
  end

  test "labels: labelAt answers a node's label place whatever the rule says of it" do
    label = js_module("mind_graph/labels", "m.labelAt({ index: 1, positions: new Float32Array([0, 0, 50, 40]), radii: [6, 8], camera: { k: 2, tx: 10, ty: 5 } })")

    assert_equal({ "index" => 1, "alpha" => 1, "x" => 122, "y" => 85 }, label)
    assert_equal [ 4, 14 ], js_module("mind_graph/labels", "[m.LABEL_GAP, m.LABEL_HEIGHT]")
  end

  test "labels: zoomed out only the first of the order are labelled, zoomed in more are" do
    count = ->(k) do
      js_module("mind_graph/labels", <<~JS)
        (() => {
          const n = 400
          const positions = new Float32Array(n * 2)
          for (let i = 0; i < n; i++) { positions[i * 2] = (i % 20) * 400; positions[i * 2 + 1] = Math.floor(i / 20) * 400 }
          const order = Array.from({ length: n }, (_, i) => i)
          return m.chooseLabels({ free: new Set(), order, positions, widths: new Array(n).fill(60), radii: new Array(n).fill(8),
            camera: { k: #{k}, tx: 0, ty: 0 }, width: 100000, height: 100000, always: new Set() }).map((label) => label.index)
        })()
      JS
    end

    few = count.call(0.5)
    more = count.call(2)

    assert_equal (0...few.size).to_a, few, "the best-connected come first"
    assert_operator few.size, :<, 20
    assert_operator more.size, :>, few.size * 4
  end

  test "labels: a label that would overlap a better-connected node's is left out" do
    labelled = js_module("mind_graph/labels", <<~JS)
      m.chooseLabels({ free: new Set(), order: [0, 1, 2], positions: new Float32Array([0, 0, 10, 2, 0, 200]), widths: [80, 80, 80], radii: [8, 8, 8],
        camera: { k: 1, tx: 100, ty: 100 }, width: 1000, height: 1000, always: new Set() }).map((label) => label.index)
    JS

    assert_equal [ 0, 2 ], labelled
  end

  test "labels: the always set is labelled at any zoom, at full strength, and first" do
    labels = js_module("mind_graph/labels", <<~JS)
      m.chooseLabels({ free: new Set(), order: [0, 1, 2], positions: new Float32Array([0, 0, 10, 2, 0, 200]), widths: [80, 80, 80], radii: [8, 8, 8],
        camera: { k: 0.05, tx: 100, ty: 100 }, width: 1000, height: 1000, always: new Set([1]) })
    JS

    assert_equal 1, labels.first["index"]
    assert_equal 1, labels.first["alpha"]
  end

  # Spec §5.2 says both "labels never overlap" and "the selection, its
  # neighbours and the focus are always labelled"; where two of them overlap,
  # no-overlap wins and the `always` Set's own order decides who keeps the
  # place (`app.js` puts the selected node in first).
  test "labels: of two overlapping members of the always set the first in the set wins, whatever the order says" do
    labelled = js_module("mind_graph/labels", <<~JS)
      m.chooseLabels({ free: new Set(), order: [0, 1, 2], positions: new Float32Array([0, 0, 10, 2, 0, 200]), widths: [80, 80, 80], radii: [8, 8, 8],
        camera: { k: 1, tx: 100, ty: 100 }, width: 1000, height: 1000, always: new Set([1, 0]) }).map((label) => label.index)
    JS

    assert_equal [ 1, 2 ], labelled
  end

  test "labels: a member of the always set the filter hides (not in the order) gets no label" do
    labelled = js_module("mind_graph/labels", <<~JS)
      m.chooseLabels({ free: new Set(), order: [0, 2], positions: new Float32Array([0, 0, 300, 2, 0, 200]), widths: [80, 80, 80], radii: [8, 8, 8],
        camera: { k: 1, tx: 100, ty: 100 }, width: 1000, height: 1000, always: new Set([1]) }).map((label) => label.index)
    JS

    assert_equal [ 0, 2 ], labelled
  end

  test "labels: a node outside the canvas gets no label, and a label sits right of its node" do
    labels = js_module("mind_graph/labels", <<~JS)
      m.chooseLabels({ free: new Set(), order: [0, 1], positions: new Float32Array([50, 50, 5000, 50]), widths: [80, 80], radii: [8, 8],
        camera: { k: 1, tx: 0, ty: 0 }, width: 300, height: 300, always: new Set([1]) })
    JS

    assert_equal [ 0 ], labels.map { |label| label["index"] }
    assert_equal [ 62, 50 ], labels.first.values_at("x", "y")
  end

  test "camera: zooming at either limit still keeps the point under the pointer" do
    %w[1000 0.000001].each do |factor|
      point = js_module("mind_graph/camera", "(() => { const c = m.zoomAt({ k: 1, tx: 30, ty: -20 }, 100, 80, #{factor}); return m.toScreen(c, m.toGraph({ k: 1, tx: 30, ty: -20 }, 100, 80)[0], m.toGraph({ k: 1, tx: 30, ty: -20 }, 100, 80)[1]) })()")
      assert_in_delta 100, point[0], 0.001
      assert_in_delta 80, point[1], 0.001
    end
  end

  test "camera: fit of a tall box is limited by the height" do
    result = js_module("mind_graph/camera", <<~JS)
      (() => {
        const box = { minX: -100, minY: -500, maxX: 100, maxY: 500 }
        const c = m.fit(box, 800, 600)
        return { k: c.k, top: m.toScreen(c, 0, box.minY), bottom: m.toScreen(c, 0, box.maxY), middle: m.toScreen(c, 0, 0) }
      })()
    JS

    assert_in_delta 0.48, result["k"], 0.001
    assert_in_delta 60, result["top"][1], 0.01
    assert_in_delta 540, result["bottom"][1], 0.01
    assert_equal [ 400, 300 ], result["middle"].map(&:round)
  end

  test "camera: bounds skip positions that are not laid out yet, and fit never returns NaN" do
    assert_equal({ "minX" => 5, "minY" => 6, "maxX" => 15, "maxY" => 16 },
      js_module("mind_graph/camera", "m.bounds(new Float32Array([NaN, NaN, 5, 6, 15, 16, 7, NaN]), [0, 1, 2, 3])"))
    assert_nil js_module("mind_graph/camera", "m.bounds(new Float32Array([NaN, NaN, NaN, 1]), [0, 1])")
    camera = js_module("mind_graph/camera", "m.fit(m.bounds(new Float32Array([NaN, NaN]), [0]), 800, 600)")
    assert_equal({ "k" => 1, "tx" => 400, "ty" => 300 }, camera)
  end

  test "labels: nodes outside the canvas do not use up the budget" do
    labelled = js_module("mind_graph/labels", <<~JS)
      (() => {
        const n = 105
        const positions = new Float32Array(n * 2)
        for (let i = 0; i < 100; i++) { positions[i * 2] = -5000 - i * 100; positions[i * 2 + 1] = 50 }
        for (let i = 100; i < n; i++) { positions[i * 2] = 50 + (i - 100) * 150; positions[i * 2 + 1] = 100 }
        return m.chooseLabels({ free: new Set(), order: Array.from({ length: n }, (_, i) => i), positions, widths: new Array(n).fill(60), radii: new Array(n).fill(8),
          camera: { k: 1, tx: 0, ty: 0 }, width: 1000, height: 1000, always: new Set() }).map((label) => label.index)
      })()
    JS

    assert_equal [ 100, 101, 102, 103, 104 ], labelled
  end

  test "labels: the last quarter of the reach fades, strictly, and the rest is at full strength" do
    labels = js_module("mind_graph/labels", <<~JS)
      (() => {
        const n = 100
        const positions = new Float32Array(n * 2)
        for (let i = 0; i < n; i++) { positions[i * 2] = (i % 10) * 200; positions[i * 2 + 1] = Math.floor(i / 10) * 200 }
        return m.chooseLabels({ free: new Set(), order: Array.from({ length: n }, (_, i) => i), positions, widths: new Array(n).fill(60), radii: new Array(n).fill(8),
          camera: { k: 1, tx: 0, ty: 0 }, width: 5000, height: 5000, always: new Set() })
      })()
    JS

    assert_equal (0...40).to_a, labels.map { |label| label["index"] }
    assert_equal [ 1 ] * 30, labels.first(30).map { |label| label["alpha"] }
    fading = labels.last(10).map { |label| label["alpha"] }
    assert fading.all? { |alpha| alpha > 0 && alpha < 1 }
    assert_equal fading.sort.reverse, fading
    assert_equal fading.uniq, fading
  end

  test "labels: rank order decides which of two overlapping labels wins" do
    labelled = js_module("mind_graph/labels", <<~JS)
      m.chooseLabels({ free: new Set(), order: [1, 0, 2], positions: new Float32Array([0, 0, 10, 2, 0, 200]), widths: [80, 80, 80], radii: [8, 8, 8],
        camera: { k: 1, tx: 100, ty: 100 }, width: 1000, height: 1000, always: new Set() }).map((label) => label.index)
    JS

    assert_equal [ 1, 2 ], labelled
  end

  test "ids: a node's id is its kind and its record's id, and only the first dash separates them" do
    assert_equal [ "post-12", "12", "blog", "owner/a-b", "posts" ],
      js_module("mind_graph/ids", '[m.nodeId("post", 12), m.recordId("post-12"), m.recordId("type-blog"), m.recordId("type-owner/a-b"), m.recordId("all-posts")]')
  end

  # ---- Pages in the mind graph (spec §4; design answers, all four parts) ----

  SOLID = [].freeze
  DASHED = [ 3, 2.5 ].freeze

  # Pages spec §4, the status table: one rule for a page and a post, and warn
  # means "scheduled" (third design answers). Read from what the renderer
  # asks of the context: a dashed outline cannot be told from a solid one by
  # one pixel. A corner dot is a surface disk (its 1.5px ring) under a dot.
  CORNER = ->(colour) { [ [ "fill", "circle", 4, "surface" ], [ "fill", "circle", 2.5, colour ] ] }

  test "marks: a page is a 14 by 10 card, Home 18 by 13, in each of the five looks" do
    live, draft, scheduled, changed, pending, home = marks_drawn([
      { kind: "page" }, { kind: "page", status: "draft" }, { kind: "page", status: "scheduled" },
      { kind: "page", changes: "unpublished" }, { kind: "page", changes: "scheduled" }, { kind: "page", home: true }
    ])

    assert_equal [ [ "fill", "box", 14, 10, 4, "page" ] ], live
    assert_equal [ [ "fill", "box", 14, 10, 4, "surface" ], [ "stroke", "box", 14, 10, 4, "meta", 1.5, DASHED ] ], draft
    assert_equal [ [ "fill", "box", 14, 10, 4, "surface" ], [ "stroke", "box", 14, 10, 4, "dim", 1.5, SOLID ], [ "fill", "circle", 2, "warn" ] ], scheduled
    assert_equal live + CORNER.call("dim"), changed, "unpublished changes: a dim corner dot"
    assert_equal live + CORNER.call("warn"), pending, "a change scheduled: a warn corner dot"
    assert_equal [ [ "fill", "box", 18, 13, 4, "page" ] ], home
  end

  test "marks: a filled post in each of the five looks, a draft dashed in meta" do
    live, draft, scheduled, changed, pending = marks_drawn([
      {}, { status: "draft" }, { status: "scheduled" }, { changes: "unpublished" }, { changes: "scheduled" }
    ])

    # A live post's own outline is centred on its edge, as before pages came
    # (left for the designer): its outer edge is at 7.75.
    assert_equal [ [ "fill", "circle", 7, "cat-1" ], [ "stroke", "circle", 7.75, "cat-1", 1.5, SOLID ] ], live
    assert_equal [ [ "fill", "circle", 7, "surface" ], [ "stroke", "circle", 7, "meta", 1.5, DASHED ] ], draft
    assert_equal [ [ "fill", "circle", 7, "surface" ], [ "stroke", "circle", 7, "dim", 1.5, SOLID ], [ "fill", "circle", 2, "warn" ] ], scheduled
    assert_equal live + CORNER.call("dim"), changed
    assert_equal live + CORNER.call("warn"), pending
  end

  # Third design answers, "Ring types": the type's mark inside a 1.5px ring,
  # so the five looks are a filled post's, drawn at 4/7 of the radius.
  test "marks: a ring type is its type's mark inside a thin ring, in the same five looks, a retired type's has its stroke, and the inner mark is 4/7 rounded to half a pixel" do
    ring = [ [ "fill", "circle", 7, "surface" ], [ "stroke", "circle", 7, "cat-1", 1.5, SOLID ] ]
    live, draft, scheduled, changed, pending, retired, retired_draft = marks_drawn([
      { colour_index: 7 }, { colour_index: 7, status: "draft" }, { colour_index: 7, status: "scheduled" }, { colour_index: 7, changes: "unpublished" },
      { colour_index: 7, changes: "scheduled" }, { colour_index: nil }, { colour_index: nil, status: "draft" }
    ])

    assert_equal ring + [ [ "fill", "circle", 4, "cat-1" ] ], live, "the ring at radius 7 with a filled radius-4 disk"
    assert_equal ring + [ [ "fill", "circle", 4, "surface" ], [ "stroke", "circle", 4, "meta", 1.5, DASHED ] ], draft
    assert_equal ring + [ [ "fill", "circle", 4, "surface" ], [ "stroke", "circle", 4, "dim", 1.5, SOLID ], [ "fill", "circle", 2, "warn" ] ], scheduled
    assert_equal live + CORNER.call("dim"), changed
    assert_equal live + CORNER.call("warn"), pending
    grey = [ [ "fill", "circle", 7, "surface" ], [ "stroke", "circle", 7, "meta", 1.5, SOLID ] ]
    assert_equal grey + [ [ "fill", "circle", 4, "meta" ], [ "stroke", "line", "meta", 1.5, SOLID ] ], retired
    assert_equal grey + [ [ "fill", "circle", 4, "surface" ], [ "stroke", "circle", 4, "meta", 1.5, DASHED ], [ "stroke", "line", "meta", 1.5, SOLID ] ], retired_draft
    # Design answer H3: at every size, to the nearest half pixel.
    inner = marks_drawn([ { colour_index: 7, degree: 1 }, { colour_index: 7, degree: 4 }, { colour_index: 7, degree: 9 }, { colour_index: 7, degree: 20 } ]).map { |drawn| [ drawn[0][2], drawn[2][2] ] }
    assert_equal [ [ 7, 4 ], [ 10, 5.5 ], [ 13, 7.5 ], [ 16, 9 ] ], inner
  end

  # THE WHOLE TABLE, kind by state. The design's status table is written here
  # a second time on purpose, in the test's own words, and every mark that
  # has a state is drawn in every one: each of the twenty-five is exactly
  # what the table says, no two are the same drawing, and a draft is DASHED
  # on every mark, so no state rests on colour alone. A sixth state added to
  # `LOOKS` fails here until it is given its row.
  STATES = {
    "live" => { node: { status: "live" }, fill: :own },
    "draft" => { node: { status: "draft" }, fill: "surface", outline: [ "meta", DASHED ] },
    "scheduled" => { node: { status: "scheduled" }, fill: "surface", outline: [ "dim", SOLID ], centre: "warn" },
    "unpublished" => { node: { status: "live", changes: "unpublished" }, fill: :own, corner: "dim" },
    "change_scheduled" => { node: { status: "live", changes: "scheduled" }, fill: :own, corner: "warn" }
  }.freeze
  # `shape` is the mark that carries the state; `ring` what a ring type draws
  # round it first; `edged` the outline a filled post has in its own hue, by
  # its outer edge. Every other outline is INSIDE its mark: an outlined mark
  # is as large as a filled one (the ruling on Task 5's review).
  STATED_MARKS = {
    "page" => { node: { kind: "page" }, shape: [ "box", 14, 10, 4 ], own: "page" },
    "Home" => { node: { kind: "page", home: true }, shape: [ "box", 18, 13, 4 ], own: "page" },
    "filled post" => { node: { colour_index: 3 }, shape: [ "circle", 7 ], own: "cat-3", edged: [ "circle", 7.75 ] },
    "ring post" => { node: { colour_index: 9 }, shape: [ "circle", 4 ], own: "cat-3", ring: [ "circle", 7 ] },
    "retired post" => { node: { colour_index: nil }, shape: [ "circle", 4 ], own: "meta", ring: [ "circle", 7 ], struck: true }
  }.freeze

  test "marks: every mark that has a state is drawn in each of the five looks exactly as the table says, no two alike, and a draft is dashed on every one" do
    table = js_module("mind_graph/marks", "m.LOOKS")
    assert_equal STATES.keys, table.keys, "the looks table and the test's own do not hold the same states"
    cases = STATED_MARKS.to_a.product(STATES.to_a)
    assert_equal STATES.keys * STATED_MARKS.size, js_module("mind_graph/marks", "#{cases.map { |(_, mark), (_, state)| mark[:node].merge(state[:node]) }.to_json}.map(m.lookOf)")

    drawn = marks_drawn(cases.map { |(_, mark), (_, state)| mark[:node].merge(state[:node]) })

    cases.zip(drawn).each do |((kind, mark), (name, state)), got|
      shape, own = mark[:shape], mark[:own]
      expected = mark[:ring] ? [ [ "fill", *mark[:ring], "surface" ], [ "stroke", *mark[:ring], own, 1.5, SOLID ] ] : []
      expected << [ "fill", *shape, state[:fill] == :own ? own : state[:fill] ]
      expected << [ "stroke", *mark[:edged], own, 1.5, SOLID ] if mark[:edged] && state[:fill] == :own
      expected << [ "stroke", *shape, state[:outline][0], 1.5, state[:outline][1] ] if state[:outline]
      expected << [ "fill", "circle", 2, state[:centre] ] if state[:centre]
      expected << [ "stroke", "line", own, 1.5, SOLID ] if mark[:struck]
      expected += CORNER.call(state[:corner]) if state[:corner]
      assert_equal expected, got, "#{kind}, #{name}"
      assert_equal name == "draft", got.any? { |entry| entry.first == "stroke" && entry.last == DASHED }, "#{kind}, #{name}: dashed is the draft's and nobody else's"
    end
    assert_equal cases.size, drawn.uniq.size, "two combinations are the same drawing"
    # A state the data does not know is drawn live, and a draft's stale mark
    # of changes draws no corner dot: the corner is a live record's.
    assert_equal %w[live draft scheduled], js_module("mind_graph/marks", '[{ status: "archived" }, { status: "draft", changes: "unpublished" }, { status: "scheduled", changes: "scheduled" }].map(m.lookOf)')
  end

  # Where each part is, from the mark's centre, to the hundredth of a pixel
  # (design answers G3, H3): the centre dot in the middle; the corner dot's
  # centre 1px in from a card's bottom-right corner, and for a circle 1px in
  # from its edge on the 45 degree line -- a ring type's on its OUTER ring,
  # whatever the size; the retired type's stroke through the whole mark.
  test "marks: the centre dot is in the middle and the corner dot one pixel in from the mark's bottom-right corner, on the outer ring of a ring type" do
    at = ->(nodes) { marks_drawn(nodes, places: true).map { |drawn| drawn.select { |entry| entry[2] == "fill" && entry[3] == "circle" && [ 2, 2.5 ].include?(entry[4]) }.map { |entry| entry.first(2) } } }

    assert_equal [ [ [ 0, 0 ] ], [ [ 0, 0 ] ], [ [ 0, 0 ] ], [ [ 0, 0 ] ] ],
      at.call([ { kind: "page", status: "scheduled" }, { kind: "page", home: true, status: "scheduled" }, { status: "scheduled" }, { colour_index: 7, status: "scheduled", degree: 20 } ])
    assert_equal [ [ [ 6, 4 ] ], [ [ 8, 5.5 ] ], [ [ 4.24, 4.24 ] ], [ [ 4.24, 4.24 ] ], [ [ 10.61, 10.61 ] ], [ [ 10.61, 10.61 ] ] ],
      at.call([ { kind: "page", changes: "unpublished" }, { kind: "page", home: true, changes: "scheduled" }, { changes: "unpublished" },
                { colour_index: 7, changes: "unpublished" }, { degree: 20, changes: "scheduled" }, { colour_index: 7, degree: 20, changes: "scheduled" } ])
    # Every other part of every mark is centred on the node.
    centred = marks_drawn([ { kind: "page" }, { kind: "page", home: true, status: "draft" }, { colour_index: 7 }, { kind: "type", id: "type-a" }, { kind: "type", id: "type-b", colour_index: 8 },
                            { kind: "type", id: "type-gone", colour_index: nil }, { kind: "tag" }, { kind: "more", title: "+92 more" } ], places: true)
    assert_equal [ [ 0, 0 ] ], centred.flatten(1).map { |entry| entry.first(2) }.uniq
  end

  # Design answers G1 to G3, H3 and H4: the hub's inner ring; a ring type's
  # hub, a ring in the hue round a filled centre; a retired type's hub, the
  # same shape in dim with a DASHED ring, so the two differ by more than
  # colour; "All posts" filled; and the pill, which grows to fit its words.
  test "marks: a type hub is a 12px circle in its colour with a surface ring, a ring type's a ring round a centre, All posts filled in dim, a retired type's a dashed outline in dim, a tag a square, more a pill with its words" do
    type, ring_type, all, retired, tag, more, long = marks_drawn([
      { kind: "type", id: "type-blog" }, { kind: "type", id: "type-b", colour_index: 8 }, { kind: "type", id: "all-posts", colour_index: nil },
      { kind: "type", id: "type-gone", colour_index: nil }, { kind: "tag" }, { kind: "more", title: "+92 more" }, { kind: "more", title: "+1,980 more", width: 82 }
    ])

    # The inner ring's outer edge is 1.5px inside the hub's radius: at 4.5.
    assert_equal [ [ "fill", "circle", 6, "cat-1" ], [ "stroke", "circle", 4.5, "surface", 1.5, SOLID ] ], type
    assert_equal [ [ "fill", "circle", 6, "surface" ], [ "stroke", "circle", 6, "cat-2", 1.5, SOLID ], [ "fill", "circle", 3, "cat-2" ] ], ring_type
    assert_equal [ [ "fill", "circle", 6, "dim" ], [ "stroke", "circle", 4.5, "surface", 1.5, SOLID ] ], all
    assert_equal [ [ "fill", "circle", 6, "surface" ], [ "stroke", "circle", 6, "dim", 1.5, DASHED ], [ "fill", "circle", 2, "dim" ] ], retired
    # A tag's square is as it was before pages came: its outline on its edge.
    assert_equal [ [ "fill", "box", 9, 9, "surface" ], [ "stroke", "box", 10.5, 10.5, "meta", 1.5, SOLID ] ], tag
    assert_equal [ [ "fill", "box", 60, 16, 8, "surface" ], [ "stroke", "box", 60, 16, 8, "line", 1, SOLID ], [ "text", "+92 more", "count", "dim" ] ], more
    assert_equal [ [ "fill", "box", 82, 16, 8, "surface" ], [ "stroke", "box", 82, 16, 8, "line", 1, SOLID ], [ "text", "+1,980 more", "count", "dim" ] ], long
    # A hub has no state: whatever the data says of one, it is drawn the same.
    assert_equal [ type, retired ], marks_drawn([ { kind: "type", id: "type-blog", status: "draft", changes: "unpublished" }, { kind: "type", id: "type-gone", colour_index: nil, status: "scheduled" } ])
  end

  test "marks: a page's, a type's and the pill's size does not follow its connections, the pill is as wide as its words need and never under 60, and the layout keeps a box's diagonal clear" do
    sizes = js_module("mind_graph/marks", <<~JS)
      [ { kind: "page", degree: 1 }, { kind: "page", degree: 40 }, { kind: "page", home: true, degree: 2 }, { kind: "type", degree: 30 }, { kind: "more", degree: 1 }, { kind: "more", width: 82 } ]
        .map((node) => [ m.radiusFor(node), Math.round(m.collisionRadius(node) * 100) / 100 ])
    JS

    assert_equal [ [ 7, 8.6 ], [ 7, 8.6 ], [ 9, 11.1 ], [ 6, 6 ], [ 30, 31.05 ], [ 41, 41.77 ] ], sizes
    assert_equal [ { "width" => 60, "height" => 16 }, { "width" => 82, "height" => 16 } ], js_module("mind_graph/marks", '[m.boxOf({ kind: "more" }), m.boxOf({ kind: "more", width: 82 })]')
    # Asked as booleans: the driver hands an array back without a null at its end.
    assert_equal [ true, true, true ], js_module("mind_graph/marks", '[ { kind: "type" }, { kind: "post" }, { kind: "tag" } ].map((node) => m.boxOf(node) === null)'), "only a page and the pill are boxes"
    assert_equal [ 60, 60, 82, 83 ], js_module("mind_graph/marks", "[m.moreWidth(20), m.moreWidth(44), m.moreWidth(66), m.moreWidth(66.2)]"), "8px each side, a whole number of pixels, never under 60 (design answer H4)"
  end

  test "hit test: a box is pressed on the box, not on a circle as wide as it" do
    hits = js_module("mind_graph/hit_test", <<~JS)
      (() => {
        const at = (sx, sy) => m.nodeAt({ positions: Float32Array.from([ 100, 100, 300, 100 ]), indexes: [ 0, 1 ], radii: [ 30, 7 ], boxes: [ { width: 60, height: 16 }, null ],
                                          camera: { k: 1, tx: 0, ty: 0 }, sx, sy })
        return [ at(100, 100), at(128, 106), at(100, 124), at(140, 100), at(300, 109), at(100, 111) ]
      })()
    JS

    assert_equal [ 0, 0, -1, -1, 1, 0 ], hits, "inside the pill; 24px above its centre is not on it though its radius is 30; a dot keeps its circle; the least target is still 24px high"
  end

  # A page's card is 14 by 10 and Home's 18 by 13. With no slack the target
  # is the card itself, grown only to the least target of 24 pixels: a press
  # at its corner is on it, where a circle of its "radius" would not reach,
  # and one pixel outside it is not. With the app's slack of 4 Home's target
  # is 26 wide and still 24 high.
  test "hit test: a page is pressed on its card out to the corner, where a circle of its radius does not reach, and not a pixel outside it" do
    hits = js_module("mind_graph/hit_test", <<~JS)
      (() => {
        const page = (sx, sy, slack, box = { width: 14, height: 10 }, radius = 7) =>
          m.nodeAt({ positions: Float32Array.from([ 100, 100 ]), indexes: [ 0 ], radii: [ radius ], boxes: [ box ], camera: { k: 1, tx: 0, ty: 0 }, sx, sy, slack })
        const dot = (sx, sy, slack) => m.nodeAt({ positions: Float32Array.from([ 100, 100 ]), indexes: [ 0 ], radii: [ 7 ], camera: { k: 1, tx: 0, ty: 0 }, sx, sy, slack })
        const wide = { width: 40, height: 30 }
        return {
          corner: [ page(107, 105, 0), page(112, 112, 0), dot(112, 112, 0), page(113, 100, 0), page(100, 113, 0), page(113, 113, 0) ],
          // A card larger than the least target, so the card's own edge is the limit.
          card: [ page(120, 115, 0, wide, 20), page(121, 115, 0, wide, 20), page(120, 116, 0, wide, 20), page(100, 119, 0, wide, 20), page(124, 119, 4, wide, 20), page(125, 119, 4, wide, 20) ],
          home: [ page(113, 112, 4, { width: 18, height: 13 }, 9), page(114, 112, 4, { width: 18, height: 13 }, 9), page(113, 113, 4, { width: 18, height: 13 }, 9) ]
        }
      })()
    JS

    assert_equal [ 0, 0, -1, -1, -1, -1 ], hits["corner"], "the card's own corner; the corner of its 24px target, which a 24px circle misses; one pixel beyond either side"
    assert_equal [ 0, -1, -1, -1, 0, -1 ], hits["card"], "the corner of a 40 by 30 card is on it; a pixel right of it or below it is not; 19px below its centre is not though its radius is 20; the slack grows it by 4 each way"
    assert_equal [ 0, -1, -1 ], hits["home"]
  end

  # Design answer G3: the Lists line is 1.5px with round caps and a dash of
  # 0.1 / 3.5, which is what makes its dots round. A hub's line to what it
  # brings in is the faint 1px line of G2.
  LINES = { "tag" => [ "meta", 1, [ 4, 3 ], 0.8, "butt" ], "related" => [ "ink", 1.5, [], 0.35, "butt" ], "brings" => [ "faint", 1, [], 1, "butt" ],
            "lists" => [ "dim", 1.5, [ 0.1, 3.5 ], 1, "round" ], "tree" => [ "tree", 1, [], 1, "butt" ] }.freeze

  test "renderer: each kind of line has its style, one path per style, and below 40 percent zoom a shared tag's is not drawn" do
    kinds = %w[tree lists related tag brings]

    assert_equal LINES.values, lines_drawn(kinds), "in the order they are drawn: a shared tag's first, the tree's on top"
    assert_equal LINES.except("tag").values, lines_drawn(kinds, k: 0.39)
    assert_equal 5, lines_drawn(kinds, k: 0.4).size
    assert_equal 1, lines_drawn(%w[tree tree tree]).size, "three lines of one style are one path"
  end

  test "renderer: a selection brightens its own lines in ink, half a pixel wider, and keeps each kind's dash and cap" do
    assert_equal LINES.values.map { |_colour, width, dash, _alpha, cap| [ "ink", width + 0.5, dash, 0.9, cap ] }, lines_drawn(%w[tree lists related tag brings], selected: 0)
  end

  # What hangs on a mark's corners follows the mark: on a card and on the
  # pill the pin's dot is on the top-right corner and the notes badge over
  # the top-left one, not where a circle as wide as the pill would have them
  # (21px above it). A selected card's and pill's ring is a box round it.
  test "renderer: a card's and a pill's pin, notes badge and ring are on the box, and a type's ring is a circle" do
    drawn = shapes_drawn([ { kind: "page", open_notes: 3 }, { kind: "more", title: "+92 more" }, { kind: "type", id: "type-a" }, { kind: "type", id: "type-a", open_notes: 2 } ], pinned: [ 0, 1 ], hovered: 2)
    page, more, type, noted_type = drawn

    assert_includes page, [ "circle", 7, -5, 3 ], "the pin on the card's top-right corner"
    assert_includes page, [ "box", -16, -5, 14, 14, 7 ], "the badge outside the card: its right edge 2px clear of the card's left edge, its centre on the top edge"
    assert_includes page, [ "box", -16, -5, 18, 18, 9 ], "its ring, 2px of the canvas's ground all round"
    assert_includes more, [ "circle", 30, -8, 3 ], "the pill's pin on its corner, not 21px above it"
    assert_includes type, [ "circle", 0, 0, 9 ], "a hovered hub's ring: a 1px line 2.5px out, so its outer edge is 3px out"
    assert_equal type.reject { |shape| shape == [ "circle", 0, 0, 9 ] }, noted_type, "a post type carries no notes badge, whatever the data says"
    selected = shapes_drawn([ { kind: "page" }, { kind: "more", title: "+92 more" } ], selected: 0, hovered: 1)
    assert_includes selected[0], [ "box", 0, 0, 24, 20 ], "a selected card's ring: a 2px line 4px out all round, so its outer edge is 5px out"
    assert_includes selected[1], [ "box", 0, 0, 66, 22, 11 ], "a hovered pill's ring: a 1px line 2.5px out all round, ROUNDED as the pill is (its ends half its height)"
    assert_not_includes selected[1], [ "box", 0, 0, 66, 22 ], "no square-cornered box round a pill"
    assert_includes selected[0], [ "box", 0, 0, 24, 20 ], "a page's card keeps its square ring"
    square = shapes_drawn([ { kind: "more", title: "+92 more" } ], hovered: 0, round_rect: false)
    assert_includes square[0], [ "box", 0, 0, 66, 22 ], "where the canvas has no roundRect the ring is a plain box, and the frame is still drawn"
  end

  # Design answer, part one §3 and F6: a page's and a type's label in ink, a
  # post's in dim, a tag's in mono and meta; the selected one semibold and in
  # full ink whatever its kind, the hovered one in ink on its backing; and a
  # node without a label (the pill, whose words are inside it) has none drawn,
  # hovered or not.
  test "renderer: a label is ink for a page and a type, dim for a post, mono meta for a tag, full ink when selected or hovered, and the pill has none" do
    nodes = [ { kind: "page", label: "Page" }, { kind: "type", id: "type-a", label: "Type" }, { kind: "post", label: "Post" }, { kind: "tag", label: "Tag" }, { kind: "more", title: "+3 more", label: "" } ]
    labels = ->(**state) { marks_drawn(nodes, labels: true, **state).map { |drawn| drawn.select { |entry| entry.first == "text" && !entry[1].start_with?("+") }.map { |entry| entry.drop(1) } } }

    assert_equal [ [ [ "Page", "sans", "ink" ] ], [ [ "Type", "sans", "ink" ] ], [ [ "Post", "sans", "dim" ] ], [ [ "Tag", "mono", "meta" ] ], [] ], labels.call
    assert_equal [ [ "Post", "strong", "ink" ] ], labels.call(selected: 2)[2]
    assert_equal [ [ "Tag", "strongMono", "ink" ] ], labels.call(selected: 3)[3], "a selected tag's label is semibold and still mono"
    assert_equal [ [ "Tag", "strongMono", "ink" ] ], labels.call(selected: 3, hovered: 3)[3]
    assert_equal [ [ "Post", "sans", "ink" ] ], labels.call(hovered: 2)[2]
    assert_equal [ [ "Tag", "mono", "ink" ] ], labels.call(hovered: 3)[3]
    assert_equal [], labels.call(hovered: 4)[4], "a hovered pill draws no label and no backing"
    assert_empty marks_drawn(nodes, labels: true, hovered: 4)[4].select { |entry| entry.first == "fill" && entry.last == "sunken" }
  end

  test "graph data: the payload becomes nodes of five kinds, All posts, more and a retired type named by the page's own words" do
    nodes = js_module("mind_graph/graph_data", <<~JS)
      m.nodesOf({ nodes: [ { id: "post-1", title: "P" } ], tags: [ { id: "tag-1", name: "t" } ], pages: [ { id: "page-1", title: "Home", home: true } ],
                  types: [ { id: "all-posts", label: null, colour_index: null }, { id: "type-blog", label: "Blog", colour_index: 1 }, { id: "type-gone/thing", label: "gone/thing", colour_index: null } ],
                  more: [ { id: "more-type-blog", count: 3, page: "page-1", target: "type-blog" }, { id: "more-tag-1", count: 1980, page: "page-1", target: "tag-1" } ] },
                { allPosts: "All posts", more: (count) => `+${count} more`, retired: (name) => `${name} (retired)` }).map((node) => [ node.id, node.kind, node.title ])
    JS

    assert_equal [ [ "page-1", "page", "Home" ], [ "post-1", "post", "P" ], [ "tag-1", "tag", "t" ], [ "all-posts", "type", "All posts" ],
                   [ "type-blog", "type", "Blog" ], [ "type-gone/thing", "type", "gone/thing (retired)" ], [ "more-type-blog", "more", "+3 more" ], [ "more-tag-1", "more", "+1980 more" ] ], nodes,
      "a pill per target; the figure's separator is the caller's (`more`), which the app gives it"
    assert_equal [ "post-1" ], js_module("mind_graph/graph_data", 'm.nodesOf({ nodes: [ { id: "post-1", title: "P" } ], tags: [], edges: [] }, {}).map((node) => node.id)'),
      "a payload without pages, types or more is the graph of posts and tags"
  end

  test "graph data: labels go to Home, then top-level pages and type nodes, then hubs, a page ahead of a post with as many links" do
    order = js_module("mind_graph/graph_data", <<~JS)
      (() => {
        const nodes = [ { kind: "post", degree: 9 }, { kind: "page", depth: 2, degree: 3 }, { kind: "post", degree: 3 }, { kind: "type", degree: 1 },
                        { kind: "page", depth: 1, degree: 1 }, { kind: "page", depth: 0, home: true, degree: 0 }, { kind: "tag", degree: 4 }, { kind: "more", degree: 1 } ]
        const all = nodes.map((_, index) => index)
        return { order: m.orderOf(nodes, all), free: Array.from(m.freeOf(nodes, all)).sort(), some: m.orderOf(nodes, [ 2, 1 ]) }
      })()
    JS

    assert_equal [ 5, 4, 3, 0, 6, 1, 2 ], order["order"], "Home; the top-level page ahead of the type by its bonus; then by links, the page of three ahead of the post of three; the pill has its words in it and is never labelled"
    assert_equal [ 3, 4, 5 ], order["free"]
    assert_equal [ 1, 2 ], order["some"]
  end

  test "labels: the free set is labelled at any zoom and uses up none of the budget, and no overlap still wins" do
    labelled = js_module("mind_graph/labels", <<~JS)
      (() => {
        const n = 100
        const positions = new Float32Array(n * 2)
        for (let i = 0; i < n; i++) { positions[i * 2] = (i % 10) * 400; positions[i * 2 + 1] = Math.floor(i / 10) * 400 }
        positions[198] = positions[196] + 2; positions[199] = positions[197]
        const order = Array.from({ length: n }, (_, i) => i)
        const args = { order, positions, widths: new Array(n).fill(20), radii: new Array(n).fill(8), camera: { k: 0.1, tx: 0, ty: 0 }, width: 100000, height: 100000, always: new Set(), free: new Set() }
        const { free: _free, ...unnamed } = args
        let refused = null
        try { m.chooseLabels(unnamed) } catch (error) { refused = error.constructor.name }
        return { refused, plain: m.chooseLabels(args).map((label) => label.index), free: m.chooseLabels({ ...args, free: new Set([ 97, 98, 99 ]) }).map((label) => [ label.index, label.alpha ]),
                 both: m.chooseLabels({ ...args, free: new Set([ 97, 98 ]), always: new Set([ 99, 97 ]) }).map((label) => label.index),
                 hidden: m.chooseLabels({ ...args, order: order.slice(0, 97), free: new Set([ 97, 98 ]) }).map((label) => label.index),
                 first: m.chooseLabels({ ...args, free: new Set([ 0 ]) }).map((label) => label.index) }
      })()
    JS

    assert_equal [ 0 ], labelled["plain"], "at this zoom the budget is one label"
    # The free set is free only when a graph has more of it than the zoom's
    # budget, and there its labels overlap away on any small graph: a caller
    # that lost the argument would show nothing wrong in a browser test. So
    # the rule has no default for it, and such a caller throws in every frame.
    assert_equal "TypeError", labelled["refused"], "the free set has a default: a caller that forgets it is not told"
    assert_equal [ [ 97, 1 ], [ 98, 1 ], [ 0, 1 ] ], labelled["free"], "97 and 98 are free; 99 would lie on 98's and gives way; the budget's one label is still placed"
    assert_equal [ 99, 97, 0 ], labelled["both"], "the always set places first: the selection's neighbour 99 keeps the place and the free 98 gives way; a free node that is also always is placed once"
    assert_equal [ 0 ], labelled["hidden"], "a free node the filter hides (not in the order) gets no label"
    assert_equal [ 0, 1 ], labelled["first"], "the best-connected node is free: the budget's one label goes to the next"
  end

  test "the layout holds the anchor at the centre, keeps a tree line shorter than another, and gives a dragged anchor back to the centre when it is released" do
    result = using_wait_time(40) do
      page.evaluate_async_script(<<~JS, ActionController::Base.helpers.asset_path("mind_graph/layout_worker.js"), ActionController::Base.helpers.asset_path("d3-force.js"))
        const [workerUrl, d3Url, done] = arguments
        import("mind_graph/layout_client").then(({ createLayout }) => {
          let last = null
          const seen = []
          const layout = createLayout({
            workerUrl, d3Url,
            onTick: (positions) => { last = Array.from(positions) },
            onSettled: () => {
              seen.push(last)
              if (seen.length === 1) { layout.drag("page-1", 200, -100); layout.drop("page-1") }
              else if (seen.length === 2) layout.unpin([ "page-1" ])
              else { layout.stop(); done({ seen }) }
            },
            onError: (message) => done({ error: message })
          })
          layout.start([ { id: "page-1", radius: 11, anchor: true }, { id: "page-2", radius: 9 }, { id: "post-1", radius: 7 } ],
                       [ { source: "page-2", target: "page-1", kind: "tree" }, { source: "post-1", target: "page-1", kind: "lists" } ], { reducedMotion: true })
        })
      JS
    end

    assert_nil result["error"]
    rest, dragged, released = result["seen"]
    assert_equal [ 0, 0 ], rest.first(2)
    assert_operator Math.hypot(rest[2], rest[3]), :<, Math.hypot(rest[4], rest[5]) - 20, "the tree line is not the shorter one"
    assert_in_delta 200, dragged[0], 0.01
    assert_in_delta(-100, dragged[1], 0.01)
    assert_equal [ 0, 0 ], released.first(2), "a released anchor did not go back to the centre"
  end

  # The anchor is Home's place at rest and nothing more: an anchor a person
  # holds stays where they put it while the layout is warmed up around it (a
  # post added from the list does that), released it goes back to the
  # centre, and a pin (from a card) holds it where it is, which is the
  # centre.
  test "the layout leaves a held anchor where it was put while a node is added, and puts a released one back at the centre" do
    result = using_wait_time(40) do
      page.evaluate_async_script(<<~JS, ActionController::Base.helpers.asset_path("mind_graph/layout_worker.js"), ActionController::Base.helpers.asset_path("d3-force.js"))
        const [workerUrl, d3Url, done] = arguments
        import("mind_graph/layout_client").then(({ createLayout }) => {
          let last = null
          const seen = []
          const steps = [
            () => { layout.drag("page-1", 150, 50); layout.drop("page-1") },
            () => layout.add({ id: "post-2", radius: 7, x: 60, y: 60 }, [ { source: "page-1", target: "post-2", kind: "lists" } ]),
            () => layout.unpin([ "page-1" ]),
            () => layout.pin("page-1")
          ]
          const layout = createLayout({
            workerUrl, d3Url,
            onTick: (positions) => { last = Array.from(positions) },
            onSettled: () => {
              seen.push(last.slice(0, 2))
              const next = steps[seen.length - 1]
              if (next) next()
              else { layout.stop(); done({ seen }) }
            },
            onError: (message) => done({ error: message })
          })
          layout.start([ { id: "page-1", radius: 11, anchor: true }, { id: "page-2", radius: 9 }, { id: "post-1", radius: 7 } ],
                       [ { source: "page-2", target: "page-1", kind: "tree" }, { source: "post-1", target: "page-1", kind: "lists" } ], { reducedMotion: true })
        })
      JS
    end

    assert_nil result["error"]
    start, dragged, kept, released, pinned = result["seen"]
    assert_equal [ 0, 0 ], start, "at the start: the centre"
    assert_in_delta 150, dragged[0], 0.01
    assert_equal dragged, kept, "an added node moved an anchor a person holds"
    assert_equal [ [ 0, 0 ], [ 0, 0 ] ], [ released, pinned ], "released it is back at the centre, and pinned from its card it is held there"
  end

  # Every other test here draws with a theme whose values are their own
  # names, so it holds "the pill's border is the key `line`" and not "`line`
  # is `--cs-line-strong`". This one holds the map: each token is given a
  # value of its own on an element, and the whole theme read from it is
  # compared. "Warn means scheduled" rests on `warn` being `--cs-warn`.
  test "theme: every key reads the token the design names, the type hues, the fonts and the card's radius included" do
    theme = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      import("mind_graph/theme").then(({ readTheme }) => {
        const element = document.createElement("div")
        const tokens = [ "ink", "meta", "dim", "warn", "surface", "sunken", "accent", "line", "line-strong", "cat-1", "cat-2", "cat-3", "cat-4", "cat-5", "cat-6", "graph-page", "graph-tree" ]
        tokens.forEach((token) => element.style.setProperty(`--cs-${token}`, `the-${token}`))
        element.style.setProperty("--cs-mono", "MonoFace")
        element.style.setProperty("--cs-radius", "7px")
        element.style.fontFamily = "SansFace"
        document.body.append(element)
        const theme = readTheme(element)
        element.remove()
        done(theme)
      }).catch((error) => done({ error: String(error) }))
    JS

    assert_equal({
      "ink" => "the-ink", "meta" => "the-meta", "dim" => "the-dim", "warn" => "the-warn", "surface" => "the-surface", "sunken" => "the-sunken", "accent" => "the-accent",
      "line" => "the-line-strong", "faint" => "the-line", "page" => "the-graph-page", "tree" => "the-graph-tree", "categories" => (1..6).map { |slot| "the-cat-#{slot}" },
      "font" => "12px SansFace", "strongFont" => "600 12px SansFace", "countFont" => "10px MonoFace", "monoFont" => "12px MonoFace", "strongMonoFont" => "600 12px MonoFace",
      "radius" => 7
    }, theme)
  end

  # A press INSIDE a drawn shape is a press on that shape, whatever else has
  # it within its slack: a pill is 60 or more wide, so its drawn end is 30
  # pixels from its centre, and a post beside it would win by its nearer
  # centre a press that is on the pill and not on the post. Only among the
  # shapes that hold the point, or where none does among the targets that
  # reach it, does the nearer centre decide.
  test "hit test: a press inside a drawn shape selects it though a neighbour's centre is nearer, and outside every shape the nearer centre still wins" do
    hits = js_module("mind_graph/hit_test", <<~JS)
      (() => {
        // A pill at 100 (its right end at 130), a post of radius 7 at 139 (its edge at 132), a card at 300 and a dot of radius 10 on its corner.
        const at = (sx, sy) => m.nodeAt({ positions: Float32Array.from([ 100, 100, 139, 100, 300, 100, 308, 106 ]), indexes: [ 0, 1, 2, 3 ], radii: [ 30, 7, 7, 10 ],
                                          boxes: [ { width: 60, height: 16 }, null, { width: 14, height: 10 }, null ], camera: { k: 1, tx: 0, ty: 0 }, sx, sy })
        return { pill: at(129, 100), gap: at(131, 100), post: at(133, 100), both: [ at(305, 103), at(302, 101) ], beside: at(297, 110) }
      })()
    JS

    assert_equal 0, hits["pill"], "on the pill's last pixel, 29 from its centre and 10 from the post's: the pill"
    assert_equal 1, hits["gap"], "between the two, on neither: the nearer centre, as before"
    assert_equal 1, hits["post"], "on the post"
    assert_equal [ 3, 2 ], hits["both"], "on the card and on the dot at once: the nearer centre of the two"
    assert_equal 2, hits["beside"], "in the card's slack and in the dot's, on neither: the nearer centre"
  end

  # Which node the layout holds at the centre: Home in the whole graph, the
  # focus in a local view (the ruling on Task 5's review), where Home, if it
  # is drawn, is a page like any other.
  test "graph data: the anchor is Home in the whole graph and the focus in a local view, of whatever kind" do
    anchors = js_module("mind_graph/graph_data", <<~JS)
      (() => {
        const pages = [ { id: "page-2", home: false }, { id: "page-1", home: true } ]
        const whole = { nodes: [], tags: [], pages }
        return [ m.anchorOf(whole), m.anchorOf({ nodes: [], tags: [], pages: [ pages[0] ] }), m.anchorOf({ nodes: [], tags: [] }),
                 m.anchorOf({ ...whole, focus: { node_id: "page-2" } }), m.anchorOf({ ...whole, focus: { node_id: "post-9" } }), m.anchorOf({ ...whole, focus: { node_id: "tag-3" } }),
                 m.anchorOf({ ...whole, focus: { node_id: "page-1" } }) ].map((id) => id ?? "none")
      })()
    JS

    assert_equal %w[page-1 none none page-2 post-9 tag-3 page-1], anchors
  end

  # The layout's own figures, as the page hands them to the worker: a tree
  # line rests at 40 with a strength of 0.9, and a released anchor keeps 85%
  # of its way with each tick until it is within half a unit. Held as VALUES,
  # because a layout's measured outcome says them only roughly; the two tests
  # below hold that the worker does what the values say.
  test "layout parameters: the tree's spring and the anchor's ease are the configured values" do
    assert_equal({ "SPRINGS" => { "tree" => { "distance" => 40, "strength" => 0.9 } }, "EASE" => { "keep" => 0.85, "within" => 0.5 } },
      js_module("mind_graph/layout_parameters", "({ SPRINGS: m.SPRINGS, EASE: m.EASE })"))
  end

  # A released anchor EASES back to the centre like every other released
  # node, a little nearer with each tick, where it used to be there in the
  # next frame with its subtree yanked after it. (With reduced motion it is
  # simply there: the test above.)
  #
  # NOTHING IS WAITED OUT. The drag, the drop and the release are sent right
  # behind `start` (the worker takes its messages in order), the ease is
  # handed over SHORTER than the real one (half the way kept per tick: ten
  # ticks from 500 away, where the real one takes forty), and the script
  # ends with the tick that shows the anchor at the centre, not with the
  # layout's cooling down. About a fifth of a second of layout.
  test "a released anchor eases back to the centre tick by tick" do
    result = page.evaluate_async_script(<<~JS, ActionController::Base.helpers.asset_path("mind_graph/layout_worker.js"), ActionController::Base.helpers.asset_path("d3-force.js"))
      const [workerUrl, d3Url, done] = arguments
      import("mind_graph/layout_client").then(({ createLayout }) => {
        // The anchor's distance from the centre at each tick, until `enough`
        // says so or forty ticks have come (two thirds of a second: a
        // release that showed nothing by then shows nothing).
        const released = (options, enough) => new Promise((resolve, reject) => {
          const seen = []
          const layout = createLayout({
            workerUrl, d3Url,
            onTick: (positions) => {
              seen.push(Math.hypot(positions[0], positions[1]))
              if (enough(seen) || seen.length >= 40) { layout.stop(); resolve(seen) }
            },
            onSettled: () => {},
            onError: reject
          })
          layout.start([ { id: "page-1", radius: 11, anchor: true }, { id: "page-2", radius: 9 }, { id: "post-1", radius: 7 } ],
                       [ { source: "page-2", target: "page-1", kind: "tree" }, { source: "post-1", target: "page-1", kind: "lists" } ], options)
          layout.drag("page-1", 300, -400)
          layout.drop("page-1")
          layout.unpin([ "page-1" ])
        })
        const away = (seen) => seen.some((distance) => distance > 0)
        Promise.all([ released({ ease: { keep: 0.5, within: 0.5 } }, (seen) => away(seen) && seen.at(-1) === 0), released({}, away) ])
          .then(([ short, own ]) => done({ short, own })).catch((error) => done({ error: String(error) }))
      })
    JS

    assert_nil result["error"]
    # From its first tick away: the ticks before the release was taken up
    # show it at the centre. It was dropped 500 away, and each tick keeps
    # half: 250, 125, … and the tenth is within half a unit, so the centre.
    back = result["short"].drop_while(&:zero?)
    assert_not_empty back, "the released anchor was never seen away from the centre: it jumped"
    assert_in_delta 250, back[0], 0.01, "the first tick after the release is not half the way back from where the anchor was dropped: #{back}"
    assert_in_delta 125, back[1], 0.01, "the second tick is not half of what was left: #{back}"
    assert_equal 10, back.size, "nine ticks on the way and the tenth at the centre: the ease handed over was not the one used (#{back})"
    assert back.each_cons(2).all? { |before, after| after < before }, "the anchor did not come strictly nearer with every tick: #{back}"
    assert_equal 0, back.last, "the anchor did not end at the centre"
    # And with the layout's own ease, which the client sends when a caller
    # names none: 85% of the way is left after the first tick.
    assert_in_delta 425, result["own"].drop_while(&:zero?).first.to_f, 0.01, "the layout's own ease is not what a release uses: #{result["own"]}"
  end

  # The tree's spring is the one it is handed, in both its figures. Home with
  # two children, one of which has two of its own, laid out three times with
  # reduced motion (no tick is shown, so no clock is in it): with the
  # layout's own springs, with a tree line as weak as a twentieth, and with
  # one as long as any other line. A RELATION, not a figure: the stiff, short
  # line holds the branching page nearer Home than either of the others, by
  # more than any rounding or any change of tick count could move.
  test "the layout's tree line is as stiff and as short as its spring says: a weaker one and a longer one each rest the page farther from its parent" do
    result = page.evaluate_async_script(<<~JS, ActionController::Base.helpers.asset_path("mind_graph/layout_worker.js"), ActionController::Base.helpers.asset_path("d3-force.js"))
      const [workerUrl, d3Url, done] = arguments
      import("mind_graph/layout_client").then(({ createLayout }) => {
        const tree = (source, target) => ({ source, target, kind: "tree" })
        const rest = (options) => new Promise((resolve, reject) => {
          let last = null
          const layout = createLayout({
            workerUrl, d3Url,
            onTick: (positions) => { last = Array.from(positions) },
            onSettled: () => { layout.stop(); resolve(Math.hypot(last[2], last[3])) },
            onError: reject
          })
          layout.start([ "page-1", "page-2", "page-3", "page-4", "page-5" ].map((id, index) => ({ id, radius: 9, anchor: index === 0 })),
                       [ tree("page-2", "page-1"), tree("page-3", "page-1"), tree("page-4", "page-2"), tree("page-5", "page-2") ], { reducedMotion: true, ...options })
        })
        Promise.all([ rest({}), rest({ springs: { tree: { distance: 40, strength: 0.05 } } }), rest({ springs: { tree: { distance: 90, strength: 0.9 } } }) ])
          .then(([ own, weak, long ]) => done({ own, weak, long })).catch((error) => done({ error: String(error) }))
      })
    JS

    assert_nil result["error"]
    assert_operator result["own"], :<, result["weak"] - 10, "a tree line a twentieth as strong rests the page no farther from Home: the strength handed over is not used (#{result})"
    assert_operator result["own"], :<, result["long"] - 10, "a tree line of 90 rests the page no farther from Home than one of 40: the distance handed over is not used (#{result})"
    assert_operator result["own"], :>, 40, "the page rests nearer Home than its line's rest length, against the repulsion (#{result})"
  end

  private

  # Zoomed in, most of the graph is outside the canvas, and a path of long
  # dashed lines costs the rasteriser by its length whether or not it is seen
  # (measured: a dropped frame in fifty while panning 2,000 posts at the
  # largest zoom; none with this). An edge is left out only when it CAN'T
  # cross the canvas -- both ends beyond the same side -- so one whose ends
  # lie on opposite sides is still drawn.
  test "renderer: an edge with both ends beyond the same side of the canvas is not drawn, one that may cross it is" do
    drawn = renderer_calls(
      positions: [ 10, 10, -500, 50, -400, -300, 700, 50 ],
      edges: [ [ 1, 2 ], [ 1, 3 ], [ 0, 1 ], [ 2, 3 ] ]
    )

    assert_equal [ [ -500, 50, 700, 50 ], [ 10, 10, -500, 50 ], [ -400, -300, 700, 50 ] ], drawn["lines"],
      "left to left is skipped; left to right, on-canvas to left, and above-left to right are drawn"
  end

  test "renderer: a node outside the canvas is not drawn, one whose mark reaches in is" do
    drawn = renderer_calls(positions: [ 10, 10, -500, 50, -5, 50, 100, 300, 203, 50 ], edges: [])

    assert_equal [ [ 10, 10 ], [ -5, 50 ], [ 203, 50 ] ], drawn["arcs"]
  end

  # Mind graph canvas spec §5.1: four steps by the number of connections, a
  # post's a step larger than first built (the design review's mock), a tag's
  # square as it was.
  test "renderer: a node's size is one of four steps by its connections" do
    sizes = ->(kind) { js_module("mind_graph/renderer", "[1, 2, 3, 5, 6, 12, 13, 400].map((degree) => m.radiusFor({ kind: #{kind.to_json}, degree }))") }

    assert_equal [ 7, 7, 10, 10, 13, 13, 16, 16 ], sizes.call("post")
    assert_equal [ 4.5, 4.5, 6, 6, 8.25, 8.25, 10.5, 10.5 ], sizes.call("tag")
  end

  # The states of the round of 2026-10-08, read from what the renderer asks of
  # the context. A post alone is one circle; pinned, it has a second, small one
  # up and to the right of its centre; selected or hovered, a ring round the
  # same centre. A tag's rings are squares (`rect`), like its mark.
  test "renderer: a pinned node carries its mark, and a selected or hovered one a ring" do
    plain = renderer_calls(positions: [ 50, 50 ], edges: [])
    pinned = renderer_calls(positions: [ 50, 50 ], edges: [], pinned: [ 0 ])
    selected = renderer_calls(positions: [ 50, 50 ], edges: [], selected: 0)
    hovered = renderer_calls(positions: [ 50, 50 ], edges: [], hovered: 0)
    both = renderer_calls(positions: [ 50, 50 ], edges: [], selected: 0, hovered: 0, pinned: [ 0 ])

    assert_equal [ [ 50, 50, 7 ] ], plain["circles"]
    assert_equal [ [ 50, 50, 7 ], [ 55.04, 44.96, 3 ] ], pinned["circles"]
    assert_equal [ [ 50, 50, 7 ], [ 50, 50, 11 ] ], selected["circles"], "the selection's ring leaves a gap round the mark"
    assert_equal [ [ 50, 50, 7 ], [ 50, 50, 9.5 ] ], hovered["circles"]
    assert_equal [ [ 50, 50, 7 ], [ 55.04, 44.96, 3 ], [ 50, 50, 11 ] ], both["circles"], "the pin mark combines with a state, and a selected node gets the selection's ring only"
    assert_equal [ 2 ], selected["ringWidths"]
    assert_equal [ 1 ], hovered["ringWidths"]
  end

  # Notes spec §4.4, handoff "Mind graph node badge": a post with open notes
  # carries the count in a pill 14 px high on its mark's top-left corner,
  # always neutral (surface, a line, ink). Its RIGHT edge is fixed, 4 px over
  # the corner, and it grows to the left with its text. A tag has none, nor a
  # post without notes; above ninety-nine it reads "99+". Read from what the
  # renderer asks of a context that records.
  test "renderer: a post with open notes carries its count in a neutral badge that grows leftwards from the top-left corner" do
    drawn = notes_badges([ 3, 12, 120, 0, nil ], tags: [ 5 ], tag_notes: 4)

    assert_equal [
      [ "pill", 32.96, 35.96, 18, 18, 9, "surface" ], [ "pill", 34.96, 37.96, 14, 14, 7, "surface" ], [ "line", "line", 1 ], [ "text", "3", 41.96, 45.46, "ink", "count" ],
      [ "pill", 126.96, 35.96, 24, 18, 9, "surface" ], [ "pill", 128.96, 37.96, 20, 14, 7, "surface" ], [ "line", "line", 1 ], [ "text", "12", 138.96, 45.46, "ink", "count" ],
      [ "pill", 220.96, 35.96, 30, 18, 9, "surface" ], [ "pill", 222.96, 37.96, 26, 14, 7, "surface" ], [ "line", "line", 1 ], [ "text", "99+", 235.96, 45.46, "ink", "count" ]
    ], drawn.reject { |entry| entry.first == "pin" }
  end

  # Claude Design's K3 (2026-10-12), the "count badges overlap the page
  # cards" of the 2026-10-15 review: on a page's card, Home's too, the badge
  # stands OUTSIDE the card, 2px clear of its left edge, centred on its top
  # edge, and grows leftwards; a post's still reaches 4px over its corner.
  test "renderer: a page's notes badge stands outside its card, on a page and on Home, and a post's is as it was" do
    page_badge, home_badge, post_badge = shapes_drawn([ { kind: "page", open_notes: 120 }, { kind: "page", home: true, open_notes: 12 }, { open_notes: 3 } ])
      .map { |shapes| shapes.find { |shape| shape.first == "box" && shape.last == 7 } }

    assert_equal [ "box", -22, -5, 26, 14, 7 ], page_badge, "99+ on a 14 by 10 card: right edge at -9, 2px left of -7"
    assert_equal [ "box", -21, -6.5, 20, 14, 7 ], home_badge, "12 on Home's 18 by 13 card: right edge at -11"
    assert_operator post_badge[1] + post_badge[3] / 2, :>, -7 * 0.71, "a post's badge still reaches over its corner"
  end

  # Claude Design's answer of 2026-10-25 (a): a badge that lands on a
  # neighbour covers it cleanly. Every badge is drawn after every mark and
  # every label, on a 2px ring of the canvas's ground (the theme's `surface`,
  # never a colour), at its node's strength.
  test "renderer: the notes badges are drawn after every mark and label, each on a ring of the canvas's ground" do
    calls = draw_calls([ { kind: "page", open_notes: 3, label: "About" }, { label: "Neighbour" } ], positions: [ 100, 100, 70, 96 ], labels: [ 0, 1 ])
    texts = calls.each_index.select { |i| calls[i][0] == "fillText" && calls[i][1] != "3" }
    marks = calls.each_index.select { |i| calls[i][0] == "fill" && calls[i][1] != "surface" }
    # The first pill after the last label is the badge's ring (a page's card is a roundRect too, and comes earlier).
    rings = calls.each_index.select { |i| calls[i][0] == "roundRect" && i > texts.max }.first

    assert_equal 2, texts.size
    assert_not_nil rings, "a pill is drawn after the last label"
    assert_operator marks.max, :<, rings, "a badge is drawn before a label or a mark"
    assert_equal [ "fill", "surface", 1 ], calls[rings + 1], "the ring is the ground, at the node's strength"
  end

  # Claude Design's answer of 2026-10-25 (b): the badge's box is one more box
  # the labels keep clear of, by the rule that keeps labels apart; the layout
  # makes no room for it.
  test "labels: a label that would cover a notes badge is not placed, and one clear of it is" do
    labelled = js_module("mind_graph/labels", <<~JS)
      m.chooseLabels({ free: new Set(), order: [0, 1], positions: new Float32Array([0, 0, 0, 200]), widths: [80, 80], radii: [8, 8],
        camera: { k: 1, tx: 100, ty: 50 }, width: 800, height: 600, always: new Set(),
        obstacles: [ { left: 150, top: 40, right: 180, bottom: 58 } ] }).map((label) => label.index)
    JS

    assert_equal [ 1 ], labelled
  end

  test "labels: the badge boxes are a post's and a page's, ring included, and none for a tag, a type or a node without notes" do
    boxes = js_module("mind_graph/labels", <<~JS)
      m.badgeBoxes({ nodes: [ { kind: "page", open_notes: 120 }, { kind: "post", degree: 1, open_notes: 3 }, { kind: "tag", open_notes: 4 }, { kind: "type", id: "type-a", open_notes: 2 }, { kind: "post", degree: 1, open_notes: 0 } ],
        indexes: [ 0, 1, 2, 3, 4 ], positions: new Float32Array([ 100, 100, 200, 100, 300, 100, 400, 100, 500, 100 ]), radii: [ 7, 7, 4.5, 6, 7 ], camera: { k: 1, tx: 0, ty: 0 } })
    JS

    assert_equal 2, boxes.size
    assert_equal({ "left" => 63, "top" => 86, "right" => 93, "bottom" => 104 }, boxes.first)
    { "left" => 182.96, "top" => 85.96, "right" => 200.96, "bottom" => 103.96 }.each { |side, value| assert_in_delta value, boxes.second[side], 0.01, side }
  end

  # The pin's dot is at the top-right and the badge at the top-left, "so both
  # can show" (handoff): on the smallest mark, at one digit, two digits and
  # "99+", the badge's box (with its line) ends left of where the pin's dot
  # (with its ring) begins. A pill centred on the corner covered half the dot
  # at two digits and all of it at "99+".
  test "renderer: a pinned node's notes badge never reaches its pin, whatever the count" do
    drawn = notes_badges([ 1, 12, 120 ], pinned: [ 0, 1, 2 ])
    rings, pills = drawn.select { |entry| entry.first == "pill" }.each_slice(2).to_a.transpose
    pins = drawn.select { |entry| entry.first == "pin" }

    assert_equal [ 3, 3, 3 ], [ rings.size, pills.size, pins.size ]
    rings.zip(pins).each do |(_, left, _top, width, *), (_, x, _y, radius)|
      ring_right = left + width        # the ring is a fill: no line
      pin_left = x - radius - 0.75     # half the dot's 1.5px ring
      assert_operator ring_right, :<, pin_left, "the badge's ring (to #{ring_right}) reaches the pin's dot (from #{pin_left})"
    end
    assert_equal [ 14, 20, 26 ], pills.map { |pill| pill[3] }
    assert_equal [ 18, 24, 30 ], rings.map { |ring| ring[3] }
    rights = pills.each_with_index.map { |pill, index| (pill[1] + pill[3] - index * 100).round(2) }
    assert_equal [ 48.96 ] * 3, rights, "the badge's right edge moved with its width"
  end

  test "renderer: a tag's ring is a square" do
    selected = renderer_calls(positions: [ 50, 50 ], edges: [], selected: 0, tags: [ 0 ])

    assert_equal [], selected["circles"]
    # A tag of one connection has a half side of 4.5; the ring is 4 px outside.
    assert_equal [ [ 41.5, 41.5, 17, 17 ] ], selected["rects"]
  end

  # With a node selected its own edges are the bright pass and the others the
  # faded one; hovering fades nothing.
  test "renderer: a selection brightens its edges and fades the rest to 28 percent, and a hover fades nothing" do
    selected = renderer_calls(positions: [ 10, 10, 60, 10, 110, 10, 160, 10 ], edges: [ [ 0, 1 ], [ 2, 3 ] ], selected: 0)
    hovered = renderer_calls(positions: [ 10, 10, 60, 10, 110, 10, 160, 10 ], edges: [ [ 0, 1 ], [ 2, 3 ] ], hovered: 0)

    assert_equal [ [ [ 110, 10, 160, 10 ], 0.098 ], [ [ 10, 10, 60, 10 ], 0.9 ] ], selected["strokes"].reject { |lines, _| lines.nil? }
    assert_equal [ 1, 1, 0.28, 0.28 ], selected["nodeAlphas"], "the selected node and its neighbour at full strength, the others at 28%"
    assert_equal [ [ [ 10, 10, 60, 10, 110, 10, 160, 10 ], 0.35 ] ], hovered["strokes"].reject { |lines, _| lines.nil? }
    assert_equal [ 1, 1, 1, 1 ], hovered["nodeAlphas"]
  end

  # ---- The legend is the filter (pages spec §6; design answers G6, H5, H6) ----

  GRAPH_DATA = <<~JS.freeze
    (() => {
      const nodes = [ { kind: "page", home: true, depth: 0, degree: 2 }, { kind: "page", depth: 1, degree: 2 }, { kind: "post", degree: 2 }, { kind: "post", degree: 2 },
                      { kind: "tag", degree: 2 }, { kind: "type", degree: 1 }, { kind: "more", degree: 1 } ]
      const edges = [ { kind: "tree", source: 1, target: 0 }, { kind: "lists", source: 1, target: 5 }, { kind: "brings", source: 5, target: 6 },
                      { kind: "related", source: 2, target: 3 }, { kind: "tag", source: 2, target: 4 }, { kind: "tag", source: 3, target: 4 }, { kind: "brings", source: 5, target: 2 } ]
      const all = { nodes: [ "page", "post", "tag", "type" ], lines: [ "tree", "lists", "related", "tag" ] }
      const shown = (off) => {
        const on = { nodes: new Set(all.nodes.filter((name) => !off.includes(name))), lines: new Set(all.lines.filter((name) => !off.includes(`line-${name}`))) }
        const result = m.visible({ nodes, edges, on })
        return [ result.visibleNodes, result.visibleEdges ]
      }
      const labelled = m.visible({ nodes, edges, on: { nodes: new Set([ "page", "post", "type" ]), lines: new Set(all.lines) } })
      return { everything: shown([]), noRelated: shown([ "line-related" ]), noTagLines: shown([ "line-tag" ]), noLists: shown([ "line-lists" ]), noTree: shown([ "line-tree" ]), noTags: shown([ "tag" ]),
               noTypes: shown([ "type" ]), noPages: shown([ "page" ]), noPosts: shown([ "post" ]), nothing: shown(all.nodes), noLines: shown(all.lines.map((name) => `line-${name}`)),
               order: labelled.order, free: Array.from(labelled.free), counts: m.counts(nodes, edges), toggles: [ m.NODE_TOGGLES, m.LINE_TOGGLES ] }
    })()
  JS

  test "graph data: a line switched off hides only the lines, and a kind switched off hides its nodes and every line that touches one" do
    shown = js_module("mind_graph/graph_data", GRAPH_DATA)

    assert_equal [ (0..6).to_a, (0..6).to_a ], shown["everything"]
    assert_equal [ (0..6).to_a, [ 0, 1, 2, 4, 5, 6 ] ], shown["noRelated"], "every node stays"
    assert_equal [ (0..6).to_a, [ 0, 1, 2, 3, 6 ] ], shown["noTagLines"], "the tag stays, without its lines"
    assert_equal [ (0..6).to_a, [ 0, 3, 4, 5 ] ], shown["noLists"], "a hub's faint lines to its posts and to the pill go with Lists: they have no toggle of their own"
    assert_equal [ (0..6).to_a, [ 1, 2, 3, 4, 5, 6 ] ], shown["noTree"], "Home stays, without its line"
    assert_equal [ [ 0, 1, 2, 3, 5, 6 ], [ 0, 1, 2, 3, 6 ] ], shown["noTags"]
    assert_equal [ [ 0, 1, 2, 3, 4, 6 ], [ 0, 3, 4, 5 ] ], shown["noTypes"], "the type, the lists line that points at it and its faint lines; the pill stays, loose"
    assert_equal [ [ 2, 3, 4, 5, 6 ], [ 2, 3, 4, 5, 6 ] ], shown["noPages"]
    assert_equal [ [ 0, 1, 4, 5 ], [ 0, 1 ] ], shown["noPosts"], "more goes with the posts"
    assert_equal [ [], [] ], shown["nothing"]
    assert_equal [ (0..6).to_a, [] ], shown["noLines"], "with every line off every node is still there"
  end

  # THE WHOLE MATRIX: every combination of the four kinds and the four kinds
  # of line, 256 of them, each held to the rule in the test's own words
  # (worked out in the page, in one call; the answer is the combinations
  # that broke a rule, with which). The site has every kind of node and of
  # line, a pill and both of a hub's faint lines, and Home.
  MATRIX = <<~JS.freeze
    (() => {
      const nodes = [ { id: "page-1", kind: "page", home: true, depth: 0 }, { id: "page-2", kind: "page", depth: 1 }, { id: "post-1", kind: "post" }, { id: "post-2", kind: "post" },
                      { id: "tag-1", kind: "tag" }, { id: "type-blog", kind: "type" }, { id: "more-type-blog", kind: "more" } ]
      const edges = [ { kind: "tree", source: 1, target: 0 }, { kind: "lists", source: 1, target: 5 }, { kind: "lists", source: 1, target: 4 }, { kind: "brings", source: 5, target: 6 },
                      { kind: "related", source: 2, target: 3 }, { kind: "tag", source: 2, target: 4 }, { kind: "tag", source: 3, target: 4 }, { kind: "brings", source: 5, target: 2 } ]
      const kinds = [ "page", "post", "tag", "type" ], lines = [ "tree", "lists", "related", "tag" ]
      const toggle = (node) => (node.kind === "more" ? "post" : node.kind)
      const lineToggle = (edge) => (edge.kind === "brings" ? "lists" : edge.kind)
      const held = JSON.stringify(m.counts(nodes, edges))
      const before = JSON.stringify([ nodes, edges ])
      const broken = []
      let combinations = 0
      for (let bits = 0; bits < 256; bits += 1) {
        combinations += 1
        const on = { nodes: new Set(kinds.filter((_, index) => bits & (1 << index))), lines: new Set(lines.filter((_, index) => bits & (16 << index))) }
        const shown = m.visible({ nodes, edges, on })
        const said = (what) => broken.push([ bits, what ])
        const drawn = new Set(shown.visibleNodes)
        nodes.forEach((node, index) => { if (drawn.has(index) !== on.nodes.has(toggle(node))) said(`node ${node.id}`) })
        edges.forEach((edge, index) => {
          const expected = on.lines.has(lineToggle(edge)) && on.nodes.has(toggle(nodes[edge.source])) && on.nodes.has(toggle(nodes[edge.target]))
          if (shown.visibleEdges.includes(index) !== expected) said(`edge ${index}`)
        })
        if (shown.visibleEdges.some((index) => !drawn.has(edges[index].source) || !drawn.has(edges[index].target))) said("a line to a hidden node")
        if (JSON.stringify(m.counts(nodes, edges)) !== held) said("the counts moved")
        if (JSON.stringify([ nodes, edges ]) !== before) said("the data was changed")
        if (m.anchorOf({ pages: nodes.filter((node) => node.kind === "page") }) !== "page-1") said("the anchor")
        if (drawn.has(0) !== on.nodes.has("page")) said("Home")
        if (shown.order.some((index) => !drawn.has(index)) || Array.from(shown.free).some((index) => !drawn.has(index))) said("a label for a hidden node")
        if (shown.order.includes(6)) said("the pill has a label")
      }
      return { combinations, broken }
    })()
  JS

  test "graph data: over every combination of the four kinds and the four kinds of line a hidden kind's nodes and lines are gone, a line needs both its ends and its own kind, the counts and the anchor stay" do
    result = js_module("mind_graph/graph_data", MATRIX)

    assert_equal 256, result["combinations"]
    assert_equal [], result["broken"].first(5), "#{result["broken"].size} combinations broke a rule (bits: page, post, tag, type, then tree, lists, related, tag)"
  end

  test "graph data: what is shown comes with the order of its labels and the free set, and the pill has no label" do
    shown = js_module("mind_graph/graph_data", GRAPH_DATA)

    assert_equal [ 0, 1, 5, 2, 3 ], shown["order"], "Home, the top-level page and the type, then the posts; no tag (it is off) and no pill"
    assert_equal [ 0, 1, 5 ], shown["free"].sort
  end

  test "graph data: the counts are what the response holds, whatever is switched off, and a hub's faint lines are no Lists lines" do
    data = js_module("mind_graph/graph_data", GRAPH_DATA)

    assert_equal({ "nodes" => { "page" => 2, "post" => 2, "tag" => 1, "type" => 1 }, "lines" => { "tree" => 1, "lists" => 1, "related" => 1, "tag" => 2 } }, data["counts"])
    assert_equal [ Admin::MindGraphScreen::LegendComponent::NODES.map(&:to_s), Admin::MindGraphScreen::LegendComponent::LINES.map(&:to_s) ], data["toggles"],
      "the script's toggles are the legend's, in its order"
  end

  # The canvas's name (design answers G6 and H5), in the page's own words:
  # the messages are the locale file's, handed to the module as the view
  # hands them, so each sentence is read here as a screen reader says it.
  def node_set(pages: 0, types: 0, posts: 0, tags: 0, more: [], focus: nil)
    nodes = Array.new(pages) { |index| { kind: "page", id: "page-#{index + 1}" } } + Array.new(posts) { { kind: "post" } } + Array.new(tags) { { kind: "tag" } } +
            Array.new(types) { { kind: "type" } } + more.map { |count| { kind: "more", count: count } }
    nodes.first.merge!(focus) if focus
    nodes
  end

  WHOLE = { shown: 13, total: 13 }.freeze
  ALL_ON = { nodes: [], lines: [] }.freeze

  test "summary: the whole graph says its counts by type, its connections and Showing everything, in the designer's words" do
    whole, small, pair, capped = summaries(
      { nodes: node_set(pages: 9, types: 3, posts: 13, tags: 4), lines: 27, data: WHOLE },
      { nodes: node_set(pages: 1, types: 1, posts: 1, tags: 1), lines: 1, data: WHOLE },
      { nodes: node_set(posts: 2040, tags: 2), lines: 0, data: { shown: 2040, total: 2040 } },
      { nodes: node_set(pages: 212, posts: 2000, tags: 64), lines: 3000, data: { shown: 2000, total: 2040 } }
    )

    assert_equal "Mind graph: 9 pages, 3 post types, 13 posts and 4 tags, 27 connections. Showing everything.", whole
    assert_equal "Mind graph: 1 page, 1 post type, 1 post and 1 tag, 1 connection. Showing everything.", small, "each count in its singular"
    assert_equal "Mind graph: 2,040 posts and 2 tags, 0 connections. Showing everything.", pair, "a kind with nothing in view is left out, and a figure is grouped"
    assert_equal "Mind graph: 212 pages, 2,000 posts and 64 tags, 3,000 connections. Showing the 2,000 best-connected of 2,040 posts.", capped
    assert_not_includes capped, "Showing everything", "never at the cap (H5)"
  end

  test "summary: a local view names its focus and depth, a page that lists more says N of M posts and how many more are in the list" do
    focus = { focus: { kind: "page", node_id: "page-1", title: "Blog", depth: 2 }, shown: 20, total: 20 }
    blog, pills, one, alone, post = summaries(
      { nodes: node_set(pages: 7, types: 1, posts: 20, more: [ 92 ], focus: { listed_count: 112 }), lines: 30, data: focus },
      { nodes: node_set(pages: 7, types: 1, posts: 20, tags: 1, more: [ 60, 32 ], focus: { listed_count: 112 }), lines: 30, data: focus },
      { nodes: node_set(pages: 1, types: 1, posts: 20, more: [ 1 ], focus: { listed_count: 21 }), lines: 30, data: focus },
      { nodes: node_set(pages: 1, focus: { listed_count: 0 }), lines: 0, data: { focus: { kind: "page", node_id: "page-1", title: "About", depth: 1 }, shown: 0, total: 0 } },
      { nodes: node_set(posts: 3, tags: 1), lines: 3, data: { focus: { kind: "post", node_id: "post-9", title: "Small sites", depth: 1 }, shown: 3, total: 3 } }
    )

    assert_equal "Mind graph around Blog, depth 2: 7 pages, 1 post type and 20 of 112 posts. 92 more are in the list.", blog
    assert_equal "Mind graph around Blog, depth 2: 7 pages, 1 post type, 20 of 112 posts and 1 tag. 92 more are in the list.", pills, "every pill in view counts together"
    assert_equal "Mind graph around Blog, depth 2: 1 page, 1 post type and 20 of 21 posts. 1 more is in the list.", one
    assert_equal "Mind graph around About, depth 1: 1 page.", alone, "depth 1 around a page draws no post, and is not nothing"
    assert_equal "Mind graph around Small sites, depth 1: 3 posts and 1 tag.", post
    [ blog, pills, one, alone, post ].each { |summary| assert_no_match(/Showing|nearest/, summary, "a local view names no cap and never says everything") }
  end

  test "summary: what is switched off is named after the scope, kinds then lines, and with nothing in view it says why" do
    nodes = node_set(pages: 2, types: 1, posts: 3, tags: 1)
    without = ->(kinds) { nodes.each_index.reject { |index| kinds.include?(nodes[index][:kind]) } }
    tags, lines, both, all, none, pills = summaries(
      { nodes: nodes, visible: without.call(%w[tag]), lines: 3, data: WHOLE, off: { nodes: %w[tag], lines: [] } },
      { nodes: nodes, lines: 3, data: WHOLE, off: { nodes: [], lines: %w[tag] } },
      { nodes: nodes, visible: without.call(%w[page type]), lines: 1, data: WHOLE, off: { nodes: %w[page type], lines: %w[tree lists related] } },
      { nodes: nodes, visible: [], lines: 0, data: WHOLE, off: { nodes: %w[page post tag type], lines: %w[tag] } },
      { nodes: [], lines: 0, data: { shown: 0, total: 0 }, off: { nodes: %w[tag], lines: [] } },
      { nodes: node_set(pages: 2, types: 1, posts: 20, more: [ 92 ], focus: { listed_count: 112 }), visible: [ 0, 1, 22 ], lines: 2, off: { nodes: %w[post], lines: [] },
        data: { focus: { kind: "page", node_id: "page-1", title: "Blog", depth: 2 }, shown: 20, total: 20 } }
    )

    assert_equal "Mind graph: 2 pages, 1 post type and 3 posts, 3 connections. Showing everything. Tags hidden.", tags, "both, in that order: everything means no cap, not no filters"
    assert_equal "Mind graph: 2 pages, 1 post type, 3 posts and 1 tag, 3 connections. Showing everything. Shares-a-tag lines hidden.", lines
    assert_equal "Mind graph: 3 posts and 1 tag, 1 connection. Showing everything. Pages hidden. Post types hidden. Tree lines hidden. Lists lines hidden. Related lines hidden.", both
    assert_equal "Mind graph: nothing to show. All types are hidden.", all, "every kind is off: that is said once, and no line is named"
    assert_equal "Mind graph: nothing to show. No pages, posts or tags yet.", none, "nothing to draw: no toggle is named"
    assert_equal "Mind graph around Blog, depth 2: 2 pages and 1 post type. Posts hidden.", pills, "the pill goes with the posts: neither N of M nor more is said"
  end

  # A viewer with fewer than four toggles (`PostGraph::Kinds`): "all" is all
  # of THEIRS. And the one case neither of the designer's two sentences is
  # true of: nothing is drawn because no post has a connection. The summary
  # then says what the notice over the canvas says, in the notice's words,
  # so a screen reader does not hear "No pages, posts or tags yet." beside
  # "2 posts have no connections yet.".
  test "summary: with every toggle a viewer has switched off all types are hidden, and unconnected posts are not no posts" do
    posts = node_set(posts: 3, tags: 1)
    two_off, one_off, three_of_three, isolated, one_isolated, empty = summaries(
      { nodes: posts, visible: [], lines: 0, data: WHOLE, off: { nodes: %w[post tag], lines: [] }, toggles: 2 },
      { nodes: posts, visible: [ 3 ], lines: 0, data: WHOLE, off: { nodes: %w[post], lines: [] }, toggles: 2 },
      { nodes: node_set(pages: 2, tags: 1, types: 1), visible: [], lines: 0, data: WHOLE, off: { nodes: %w[page tag type], lines: %w[tree] }, toggles: 3 },
      { nodes: [], lines: 0, data: { shown: 0, total: 0, isolated: 2 } },
      { nodes: [], lines: 0, data: { shown: 0, total: 0, isolated: 1 }, off: { nodes: %w[tag], lines: [] } },
      { nodes: [], lines: 0, data: { shown: 0, total: 0, isolated: 0 } }
    )

    assert_equal "Mind graph: nothing to show. All types are hidden.", two_off
    assert_equal "Mind graph: 1 tag, 0 connections. Showing everything. Posts hidden.", one_off, "one of two is not all"
    assert_equal "Mind graph: nothing to show. All types are hidden.", three_of_three
    assert_equal "Mind graph: nothing to show. 2 posts have no connections yet.", isolated
    assert_equal "Mind graph: nothing to show. 1 post has no connections yet.", one_isolated
    assert_equal "Mind graph: nothing to show. No pages, posts or tags yet.", empty
  end

  test "summary: the view the 3,000-line rule opened says where it is and what the site holds, and no other view does" do
    home = { focus: { kind: "page", node_id: "page-1", title: "Home", depth: 1 }, shown: 0, total: 0, site: { pages: 212, posts: 2040, tags: 64 } }
    opened, plain, bare, tagless = summaries(
      { nodes: node_set(pages: 6, types: 2), lines: 7, data: home, around_home: true },
      { nodes: node_set(pages: 6, types: 2), lines: 7, data: home },
      { nodes: node_set(pages: 6, types: 2), lines: 7, data: home.except(:site), around_home: true },
      { nodes: node_set(pages: 6, types: 2), lines: 7, data: home.merge(site: { pages: 1, posts: 2040, tags: 0 }), around_home: true, off: { nodes: %w[tag], lines: [] } }
    )

    assert_equal "Mind graph around Home, depth 1: 6 pages and 2 post types. Showing the area around Home. The site has 212 pages, 2,040 posts and 64 tags.", opened
    assert_equal "Mind graph around Home, depth 1: 6 pages and 2 post types.", plain
    assert_equal plain, bare, "without the site's counts nothing is said of the site"
    assert_equal "Mind graph around Home, depth 1: 6 pages and 2 post types. Showing the area around Home. The site has 1 page and 2,040 posts. Tags hidden.", tagless
  end

  # The swatches of the legend and of the Status key are the RENDERER'S OWN
  # drawings: each is compared with what the canvas draws for the same node
  # or line, part for part, so a look that changes in `marks.js` changes
  # here too and no key can show one the canvas does not have.
  SWATCH_STATES = { "state-live" => {}, "state-draft" => { status: "draft" }, "state-scheduled" => { status: "scheduled" },
                    "state-live-with-changes" => { changes: "unpublished" }, "state-live-change-scheduled" => { changes: "scheduled" } }.freeze

  def in_hue(drawn, hue) = drawn.map { |part| part.map { |value| value == "cat-1" ? hue : value } }
  def swatch_parts(name) = swatch_drawn(name).map { |_x, _y, *rest| rest }

  test "swatches: the Status key's five looks are the canvas's own drawing of a post in each state, in ink" do
    on_canvas = marks_drawn(SWATCH_STATES.values)

    SWATCH_STATES.each_key.with_index { |name, index| assert_equal in_hue(on_canvas[index], "ink"), swatch_parts(name), name }
    assert_equal 5, SWATCH_STATES.keys.map { |name| swatch_parts(name) }.uniq.size, "no two looks are one drawing"
    assert_equal Admin::MindGraphScreen::StatusKeyComponent::STATES.map { |state| "state-#{state.to_s.dasherize}" }, SWATCH_STATES.keys, "the key's states, by Publishing::State's names"
  end

  test "swatches: a toggle's mark, the retired type, the pin and the notes badge are the canvas's own drawings, and a toggle's line its kind's style" do
    page_mark, post, tag, type, retired, noted = marks_drawn([ { kind: "page" }, {}, { kind: "tag" }, { kind: "type", id: "all-posts", colour_index: nil }, { colour_index: nil }, { open_notes: 1 } ])
    pinned = marks_drawn([ {} ], pinned: [ 0 ]).first

    assert_equal page_mark, swatch_parts("page")
    assert_equal in_hue(post, "dim"), swatch_parts("post"), "a post that names no type: in dim, as All posts is"
    assert_equal tag, swatch_parts("tag")
    assert_equal type, swatch_parts("type"), "the hub of All posts"
    assert_equal retired, swatch_parts("retired")
    assert_equal in_hue(pinned, "dim"), swatch_parts("pinned")
    assert_equal in_hue(noted, "dim"), swatch_parts("notes")
    LINES.except("brings").each do |kind, (colour, width, dash)|
      assert_equal [ [ 0, 4, "stroke", "line", colour, width, dash ] ], swatch_drawn("line-#{kind}"), "#{kind}: one line across the swatch, from its left edge at half its height"
    end
  end

  test "swatches: every swatch the page can ask for has a scene, and none is cut by its canvas" do
    sizes = Admin::MindGraphScreen::SwatchComponent::SIZES
    assert_equal sizes.keys.map(&:to_s).sort, js_module("mind_graph/swatches", "Object.keys(m.SCENES)").sort

    sizes.each do |name, (width, height)|
      swatch_drawn(name.to_s).each do |x, y, _done, shape, *rest|
        reach = shape == "circle" ? [ rest[0], rest[0] ] : shape == "box" ? [ rest[0] / 2.0, rest[1] / 2.0 ] : [ 0, 0 ]
        assert x - reach[0] >= 0 && x + reach[0] <= width && y - reach[1] >= 0 && y + reach[1] <= height, "#{name}: a #{shape} at #{x}, #{y} reaching #{reach.inspect} leaves its #{width} by #{height} canvas"
      end
    end
    error = js_module("mind_graph/swatches", '(() => { try { m.drawSwatch({}, {}, "no-such", { width: 1, height: 1 }); return null } catch (error) { return error.message } })()')
    assert_equal 'mind graph: no swatch "no-such"', error, "an unknown swatch is loud, not blank"
  end

  # A ROW'S MARK (pages spec §7; design answer H2) is the renderer's own
  # drawing of that kind of node, scaled as a whole: compared part for part
  # with what the canvas draws, so a hub's row cannot show a look the canvas
  # does not have, and a look that changes in `marks.js` changes here too.
  test "row marks: a page's and a post type's are the canvas's own drawings scaled to 10 pixels, each hub its own, in the middle of its canvas" do
    on_canvas = marks_drawn([ { kind: "page" }, { kind: "type", id: "type-a", colour_index: 1 }, { kind: "type", id: "type-b", colour_index: 8 },
                              { kind: "type", id: "type-c", colour_index: nil }, { kind: "type", id: "all-posts", colour_index: nil } ])
    rows = [ [ "page", nil ], [ "type", "1" ], [ "type", "8" ], [ "type", "retired" ], [ "type", "all-posts" ] ].map { |kind, of| row_mark_drawn(kind, of) }

    rows.each_with_index { |row, index| assert_equal on_canvas[index], row["parts"].map { |_x, _y, *rest| rest }, "row #{index}" }
    assert_equal 5, rows.map { |row| row["parts"].map { |_x, _y, *rest| rest } }.uniq.size, "a filled hub, a ring type's, a retired type's and All posts are four drawings, and a page's a fifth"
    assert_equal [ (10 / 14.0).round(4) ] + [ (10 / 12.0).round(4) ] * 4, rows.map { |row| row["scale"].round(4) }, "a page's card is 10 wide where the canvas has 14, a hub 10 across where it has 12"
    rows.each do |row|
      width, height = row.values_at("width", "height")
      x, y = row["parts"].first.first(2)
      assert_in_delta width / 2.0, x * row["scale"], 0.01, "the mark is in the middle of its canvas"
      assert_in_delta height / 2.0, y * row["scale"], 0.01
    end
    assert_equal [ [ 10, 8 ], [ 10, 10 ] ], [ rows.first, rows.last ].map { |row| row.values_at("width", "height") }, "a page's canvas is high enough for 10 * 10 / 14 pixels"
  end

  test "row marks: a mark's canvas says what it shows, is decoration, and is drawn only once it is asked" do
    marks = js_module("mind_graph/swatches", <<~JS)
      [ { kind: "page", id: "page-1", status: "draft", home: true }, { kind: "type", id: "type-blog", colour_index: 3 }, { kind: "type", id: "type-old", colour_index: null },
        { kind: "type", id: "all-posts", colour_index: null }, { kind: "type", id: "type-x", colour_index: 14 } ]
        .map((node) => m.markCanvas(node)).map((canvas) => [ canvas.tagName, canvas.dataset.mark, canvas.dataset.markOf ?? "-", canvas.getAttribute("aria-hidden"), canvas.width, canvas.height ])
    JS

    assert_equal [ [ "CANVAS", "page", "-", "true", 10, 8 ], [ "CANVAS", "type", "3", "true", 10, 10 ], [ "CANVAS", "type", "retired", "true", 10, 10 ],
                   [ "CANVAS", "type", "all-posts", "true", 10, 10 ], [ "CANVAS", "type", "14", "true", 10, 10 ] ], marks,
      "a page's mark says nothing of the page (its state and Home are the canvas's and the card's to show)"
  end

  # The selection card, asked directly with plain nodes (pages spec §7): no
  # layout, no canvas and no request (a node with no open notes fetches
  # none). Each message is its key's last segments with its values, so a
  # test reads which sentence was asked for and with what.
  CARD_SCRIPT = <<~JS.freeze
    (() => {
      const container = document.createElement("aside")
      document.body.append(container)
      const text = { t: (key, values = {}) => `${key.split(".").slice(2).join(".")}(${Object.values(values).join(",")})`, locale: () => "en" }
      const urls = { postFocus: "/g?post=__ID__", tagFocus: "/g?tag=__ID__", tagPosts: "/posts?tag=__NAME__", postNotes: "/notes/post/__ID__/threads", pageFocus: "/g?page=__ID__", pageNotes: "/notes/page/__ID__/threads" }
      const card = m.createCard(container, { text, number: (value) => new Intl.NumberFormat("en").format(value), urls, typeLabels: { blog: "Blog" }, dotClasses: Array(12).fill("dot"), buttonClasses: { primary: "primary", secondary: "secondary" }, onClose() {}, onPin() {}, onChange() {} })
      // The card top to bottom: each child as what it is and what it says.
      const part = (child) => child.matches("[data-mind-graph-card-notes]") ? [ "notes", child.dataset.notesType, child.dataset.notesId, child.querySelector("textarea").getAttribute("aria-label") ]
        : child.matches("[data-mind-graph-card-close]") ? [ "close" ]
        : child.tagName === "H2" ? [ "title", child.textContent ]
        : child.querySelector("a, button") ? [ "actions", ...Array.from(child.querySelectorAll("a, button"), (control) => [ control.tagName, control.textContent, control.getAttribute("href") ?? "-", control.className ]) ]
        : child.tagName === "P" ? [ "counts", ...Array.from(child.children, (item) => [ item.textContent, item.getAttribute("aria-hidden") ?? "-" ]) ]
        : [ "heading", ...Array.from(child.children, (item) => item.tagName === "CANVAS" ? [ "mark", item.dataset.mark, item.dataset.markOf ?? "-", item.getAttribute("aria-hidden") ] : item.matches(".admin-status-chip") ? [ "chip", item.dataset.status ] : [ "words", item.textContent, item.getAttribute("aria-hidden") ?? "-" ]) ]
      const read = () => Array.from(container.children, part)
      const chip = () => {
        const found = container.querySelector(".admin-status-chip")
        if (!found) return "none"
        const seen = found.querySelector("span[aria-hidden='true'][data-chip-seen]")
        return { status: found.dataset.status, row: found.parentElement === container.firstElementChild ? "first" : found.parentElement.matches("[data-chip-row]") && found.parentElement.previousElementSibling === container.firstElementChild ? "own" : "?", dots: Array.from(found.querySelectorAll("span.rounded-full"), (dot) => [ dot.className.match(/bg-[a-z]+/)[0], dot.getAttribute("aria-hidden") ]),
                 seen: seen ? Array.from(seen.childNodes).flatMap((item) => item.nodeType === 3 || item.childElementCount === 0 ? [ item.textContent ] : Array.from(item.childNodes, (piece) => piece.nodeType === 3 ? piece.textContent : "(dot)")) : "-",
                 heard: found.querySelector(".sr-only")?.textContent ?? "-", text: found.textContent }
      }
      return { container, card, read, chip }
    })()
  JS

  # Pages spec §7; design answer, part one §5: "path, status pill, '4 child
  # pages · lists 112 posts', Open page / Focus / Pin; the notes list under
  # the title as on post cards".
  test "card: a page's card is its path and state, its title, its two counts, its notes, then Open page, Focus and Pin, and Home's is the same" do
    result = js_module("mind_graph/card", <<~JS)
      (() => {
        const { container, card, read } = #{CARD_SCRIPT}
        const page = { id: "page-7", kind: "page", title: "<b>Blog</b>", path: "/blog/<i>x</i>", depth: 1, home: false, status: "live", changes: null, url: "/cs-studio/pages/7?locale=de", degree: 3, child_count: 4, listed_count: 112, open_notes: 0 }
        card.show(page)
        const blog = read()
        const named = [ container.getAttribute("aria-labelledby"), container.querySelector("h2").id, container.hidden, container.querySelectorAll("b, i").length ]
        const marked = Array.from(container.querySelectorAll("canvas[data-mark]"), (canvas) => canvas.getContext("2d").getImageData(0, 0, canvas.width, canvas.height).data.some((value) => value > 0))
        let followed = null
        container.querySelector("a[data-mind-graph-card-open]").addEventListener("click", (event) => { event.preventDefault(); followed = event.currentTarget.getAttribute("href") })
        card.open()
        card.show({ ...page, id: "page-1", title: "Home", path: "/", depth: 0, home: true, child_count: 1, listed_count: 1, url: "/cs-studio/pages/1" })
        const home = read()
        card.show({ ...page, id: "page-9", title: "Stray", path: null, child_count: 0, listed_count: 0, status: "retired?" })
        const stray = read()
        card.show(page, { pinned: true, pinnable: false })
        const pin = [ container.querySelector("[data-mind-graph-card-pin]").textContent, container.querySelector("[data-mind-graph-card-pin]").hidden ]
        card.hide()
        const hidden = [ container.hidden, container.childElementCount ]
        // A kind with no card (a pill, or one a later build adds): nothing is shown and nothing throws.
        const cardless = [ "more", "constructor", undefined ].map((kind) => { try { return [ card.show({ id: "x-1", kind, title: "X" }), container.hidden, container.childElementCount ] } catch (error) { return String(error) } })
        card.show(page)
        const over = [ card.show({ id: "more-type-a", kind: "more", title: "+2 more" }), container.querySelector("h2").textContent, container.hidden ]
        card.hide()
        container.remove()
        return { blog, named, marked, followed, home, stray, pin, hidden, cardless, over }
      })()
    JS

    assert_equal [ [ "heading", [ "mark", "page", "-", "true" ], [ "words", "/blog/<i>x</i>", "-" ], [ "chip", "live" ] ],
                   [ "title", "<b>Blog</b>" ],
                   [ "counts", [ "card.child_pages(4,4)", "-" ], [ "·", "true" ], [ "card.lists_posts(112,112)", "-" ] ],
                   [ "notes", "page", "7", "card.notes.label_page()" ],
                   [ "actions", [ "A", "card.open_page()", "/cs-studio/pages/7?locale=de", "primary" ], [ "A", "card.focus()", "/g?page=7", "secondary" ], [ "BUTTON", "card.pin()", "-", "secondary" ] ],
                   [ "close" ] ], result["blog"]
    assert_equal [ "mind-graph-card-title", "mind-graph-card-title", false, 0 ], result["named"], "the card is named by its title, and a title and a path are text"
    assert_equal [ true ], result["marked"], "the page's mark is the renderer's drawing, painted once the card is in the document"
    assert_equal "/cs-studio/pages/7?locale=de", result["followed"], "Enter on a selected page presses Open page: the address is the one the server built"
    assert_equal [ [ "words", "/", "-" ], [ "counts", [ "card.child_pages(1,1)", "-" ], [ "·", "true" ], [ "card.lists_posts(1,1)", "-" ] ], [ "notes", "page", "1", "card.notes.label_page()" ] ],
                 [ result["home"][0][2], result["home"][2], result["home"][3] ], "Home's card is a page's card"
    assert_equal [ "heading", [ "mark", "page", "-", "true" ], [ "words", "", "-" ] ], result["stray"][0], "a page with no address has none written, and a status the chip does not know has no chip"
    assert_equal [ "counts", [ "card.child_pages(0,0)", "-" ], [ "·", "true" ], [ "card.lists_posts(0,0)", "-" ] ], result["stray"][2]
    assert_equal [ [ "card.unpin()", true ], [ true, 0 ] ], result.values_at("pin", "hidden")
    assert_equal [ [ false, true, 0 ] ] * 3, result["cardless"], "a kind without a card is answered false: no card, no error, also for a name every object has"
    assert_equal [ false, "<b>Blog</b>", false ], result["over"], "and the card that is open stays as it is"
  end

  # Design answers G4 and H6: the chip keeps its three dots and says a live
  # record's second state after the label -- "● Live · Unpublished changes"
  # with no second dot, "● Live · ● Change scheduled 14 Oct" with a warn dot
  # before the second part -- and a screen reader is given the Status key's
  # own words in one sentence. The day is the server's (`change_on`).
  test "card: the chip says each of the five states, the second state after the label for the eye and in the key's words for a screen reader, on a page and on a post alike" do
    states = { draft: { status: "draft" }, scheduled: { status: "scheduled" }, live: { status: "live", changes: nil },
               live_with_changes: { status: "live", changes: "unpublished" }, live_change_scheduled: { status: "live", changes: "scheduled", change_at: "2026-10-14T09:00:00Z", change_on: "14 Oct" },
               draft_with_changes: { status: "draft", changes: "unpublished" }, unknown: { status: "archived" } }
    result = js_module("mind_graph/card", <<~JS)
      (() => {
        const { container, card, chip } = #{CARD_SCRIPT}
        const states = #{states.to_json}
        const of = (base) => Object.fromEntries(Object.entries(states).map(([ name, state ]) => { card.show({ ...base, ...state }); return [ name, chip() ] }))
        const result = { page: of({ id: "page-7", kind: "page", title: "Blog", path: "/blog", url: "/p", child_count: 0, listed_count: 0, open_notes: 0 }),
                         post: of({ id: "post-7", kind: "post", title: "Post", type: "blog", colour_index: 1, url: "/p", related_count: 0, tag_count: 0, open_notes: 0 }) }
        container.remove()
        return result
      })()
    JS

    %w[page post].each do |kind|
      chips = result[kind]
      assert_equal({ "status" => "draft", "row" => "first", "dots" => [ [ "bg-meta", "true" ] ], "seen" => "-", "heard" => "-", "text" => "card.status.draft()" }, chips["draft"], kind)
      assert_equal({ "status" => "scheduled", "row" => "first", "dots" => [ [ "bg-warn", "true" ] ], "seen" => "-", "heard" => "-", "text" => "card.status.scheduled()" }, chips["scheduled"], kind)
      assert_equal({ "status" => "live", "row" => "first", "dots" => [ [ "bg-ok", "true" ] ], "seen" => "-", "heard" => "-", "text" => "card.status.live()" }, chips["live"], kind)
      assert_equal({ "status" => "live_with_changes", "row" => "own", "dots" => [ [ "bg-ok", "true" ] ], "seen" => [ "card.status.live()", "·", "card.status.unpublished_changes()" ], "heard" => "card.status.live_with_changes()",
                     "text" => "card.status.live()·card.status.unpublished_changes()card.status.live_with_changes()" }, chips["live_with_changes"], "#{kind}: no second dot")
      assert_equal({ "status" => "live_change_scheduled", "row" => "own", "dots" => [ [ "bg-ok", "true" ], [ "bg-warn", "true" ] ],
                     "seen" => [ "card.status.live()", "·", "(dot)", "card.status.change_scheduled(14 Oct)" ], "heard" => "card.status.live_change_scheduled(14 Oct)",
                     "text" => "card.status.live()·card.status.change_scheduled(14 Oct)card.status.live_change_scheduled(14 Oct)" }, chips["live_change_scheduled"], "#{kind}: a warn dot before the second part, and the server's day")
      assert_equal "draft", chips["draft_with_changes"]["status"], "#{kind}: only a live record has a second state"
      assert_equal "card.status.draft()", chips["draft_with_changes"]["text"]
      assert_equal "none", chips["unknown"], "#{kind}: a status the chip does not know gets no chip"
    end
  end

  # A post type a page lists (design answer F1; its card is the brief's): what
  # it is, its name, how many posts of it the viewer reads, and Pin. No link:
  # the pages that list it are its neighbours on the canvas.
  test "card: a post type's card is its hub's mark, its name and how many posts it has, with Pin and no link, for a retired type and All posts too" do
    result = js_module("mind_graph/card", <<~JS)
      (() => {
        const { container, card, read } = #{CARD_SCRIPT}
        const cards = [ { id: "type-blog", kind: "type", name: "blog", title: "Blog", colour_index: 3, count: 112, degree: 2 },
                        { id: "type-talk", kind: "type", name: "talk", title: "talk (retired)", colour_index: null, count: 1, degree: 1 },
                        { id: "all-posts", kind: "type", name: null, title: "All posts", colour_index: null, count: 2040, degree: 4 },
                        { id: "type-new", kind: "type", name: "new", title: "New", colour_index: 8, degree: 1 } ].map((node) => { card.show(node); return read() })
        container.remove()
        return cards
      })()
    JS

    blog, retired, all, countless = result
    assert_equal [ [ "heading", [ "mark", "type", "3", "true" ], [ "words", "card.post_type()", "-" ] ], [ "title", "Blog" ], [ "counts", [ "card.tag_posts(112,112)", "-" ] ],
                   [ "actions", [ "BUTTON", "card.pin()", "-", "secondary" ] ], [ "close" ] ], blog
    assert_equal [ [ "heading", [ "mark", "type", "retired", "true" ], [ "words", "card.post_type()", "-" ] ], [ "title", "talk (retired)" ], [ "counts", [ "card.tag_posts(1,1)", "-" ] ] ], retired.first(3)
    assert_equal [ [ "heading", [ "mark", "type", "all-posts", "true" ], [ "words", "card.post_type()", "-" ] ], [ "title", "All posts" ], [ "counts", [ "card.tag_posts(2040,2,040)", "-" ] ] ], all.first(3)
    assert_equal [ "counts", [ "card.tag_posts(0,0)", "-" ] ], countless[2]
    assert_includes all[2].flatten, "card.tag_posts(2040,2,040)", "a figure is grouped as the messages' language groups it; the number itself only chooses the plural"
  end

  # What the card showed before pages is what it shows now: a post's and a
  # tag's, and the added post whose counts the page does not know.
  test "card: a post's card keeps its order and its notes' type, an added post's leaves the counts out, and a tag's has no notes" do
    result = js_module("mind_graph/card", <<~JS)
      (() => {
        const { container, card, read } = #{CARD_SCRIPT}
        const post = { id: "post-12", kind: "post", title: "Twelve", type: "blog", colour_index: 1, status: "live", changes: null, url: "/cs-studio/posts/12", related_count: 3, tag_count: 2, open_notes: 0 }
        const cards = [ post, { ...post, related_count: null, tag_count: null }, { id: "tag-3", kind: "tag", title: "a b&c", count: 2, degree: 2 } ].map((node) => { card.show(node); return read() })
        container.remove()
        return cards
      })()
    JS

    post, added, tag = result
    assert_equal [ [ "heading", [ "words", "", "true" ], [ "words", "Blog", "-" ], [ "chip", "live" ] ], [ "title", "Twelve" ],
                   [ "counts", [ "card.related(3,3)", "-" ], [ "·", "true" ], [ "card.tags(2,2)", "-" ] ], [ "notes", "post", "12", "card.notes.label()" ],
                   [ "actions", [ "A", "card.open_post()", "/cs-studio/posts/12", "primary" ], [ "A", "card.focus()", "/g?post=12", "secondary" ], [ "BUTTON", "card.pin()", "-", "secondary" ] ], [ "close" ] ], post
    assert_equal %w[heading title notes actions close], added.map(&:first), "a post added from the list says nothing of counts nobody counted"
    assert_equal [ [ "heading", [ "words", "", "true" ], [ "words", "card.tag()", "-" ] ], [ "title", "a b&c" ], [ "counts", [ "card.tag_posts(2,2)", "-" ] ],
                   [ "actions", [ "A", "card.show_tagged()", "/posts?tag=a%20b%26c", "primary" ], [ "A", "card.focus()", "/g?tag=3", "secondary" ], [ "BUTTON", "card.pin()", "-", "secondary" ] ], [ "close" ] ], tag
  end

  LIST_SCRIPT = <<~JS.freeze
    (() => {
      const container = document.createElement("div")
      const calls = []
      const text = { t: (key, values = {}) => `${key.split(".").slice(-2).join(".")}(${Object.values(values).join(",")})`, locale: () => "en" }
      const list = m.createList(container, { text, dotClasses: Array(12).fill("dot"), typeLabels: { blog: "Blog" }, retryClass: "retry", onSelect: (id) => calls.push([ "select", id ]), onHover: () => {},
                                             onAdd: (row) => calls.push([ "add", row.id ]), onUnlisted: (on) => calls.push([ "unlisted", on ]) })
      const read = () => Array.from(container.querySelectorAll("h2, button")).map((item) => item.tagName === "H2" ? item.textContent : [ item.querySelector(".truncate").textContent, item.lastChild.textContent, item.style.paddingInlineStart, item.getAttribute("aria-label") ])
      return { container, calls, list, read }
    })()
  JS

  test "list: four groups: Pages first, in tree order and indented by depth, then posts and tags by their connections, then the post types as the data has them" do
    rows = js_module("mind_graph/node_list", <<~JS)
      (() => {
        const { container, list, read } = #{LIST_SCRIPT}
        list.render([ { id: "post-1", kind: "post", title: "Post", degree: 1, colour_index: 1 }, { id: "tag-1", kind: "tag", title: "tag", degree: 2 },
                      { id: "page-3", kind: "page", title: "Child", degree: 9, depth: 2, order: 2, parent: "page-2" }, { id: "page-1", kind: "page", title: "Home", degree: 1, depth: 0, order: 0, parent: null },
                      { id: "page-2", kind: "page", title: "Docs", degree: 2, depth: 1, order: 1, parent: "page-1" }, { id: "page-9", kind: "page", title: "Stray", degree: 0, depth: 1, order: 3, parent: null },
                      { id: "type-blog", kind: "type", title: "Blog", degree: 4, count: 112, colour_index: 1 }, { id: "type-talk", kind: "type", title: "Talk", degree: 9, count: 1, colour_index: 8 },
                      { id: "type-gone", kind: "type", title: "gone (retired)", degree: 1, count: 0, colour_index: null }, { id: "all-posts", kind: "type", title: "All posts", degree: 1, count: 2040, colour_index: null },
                      { id: "more-type-blog", kind: "more", title: "+3 more", degree: 1, count: 3, target: "type-blog", of: "Blog" } ])
        const markOf = (button) => { const mark = button.firstElementChild; return [ mark.tagName, mark.dataset.mark ?? (mark.classList.contains("truncate") ? "truncate" : mark.className.split(" ").pop()), mark.dataset.markOf ?? "-", mark.getAttribute("aria-hidden") ?? "-" ] }
        // Where a page's row stands in the document: the row of the item its list is in, or "top". (No null: the driver drops one from an array.)
        const under = (id) => list.row(id).closest("ul").parentElement.closest("li")?.querySelector("button").dataset.nodeId ?? "top"
        return { rows: read(), marks: Array.from(container.querySelectorAll("button"), markOf),
                 under: [ "page-1", "page-2", "page-3", "page-9" ].map(under),
                 lists: Array.from(container.querySelectorAll("section"), (section) => [ section.querySelector("h2").textContent, section.querySelector("ul").getAttribute("aria-labelledby") === section.querySelector("h2").id, section.querySelector("ul").getAttribute("role") ]),
                 checkbox: [ container.firstElementChild.tagName, container.querySelector("label input").type, container.querySelector("label").textContent ] }
      })()
    JS

    assert_equal [ "list.pages(4)", [ "Home", "1", "12px", "list.select_page(Home,1)" ], [ "Docs", "2", "24px", "list.select_page(Docs,2)" ],
                   [ "Child", "9", "36px", "list.select_page(Child,9)" ], [ "Stray", "0", "24px", "list.select_page(Stray,0)" ],
                   "list.posts(1)", [ "Post", "1", "", "list.select_post(Post,1)" ], "list.tags(1)", [ "tag", "2", "", "list.select_tag(tag,2)" ],
                   "list.types(4)", [ "Blog", "112", "", "list.select_type(Blog,112)" ], [ "+3 more", "+3 more", "28px", "list.more_row(3,3,Blog,+3 more)" ], [ "Talk", "1", "", "list.select_type(Talk,1)" ],
                   [ "gone (retired)", "0", "", "list.select_type(gone (retired),0)" ], [ "All posts", "2040", "", "list.select_type(All posts,2040)" ] ], rows["rows"],
      "a page whose parent is not in the data is listed after the tree, indented once; a post type's number is its POSTS, not its connections, and the rows keep the data's order; a pill's row stands under the row of what it hangs off and is no post type: the group still counts four"
    assert_equal [ "top", "page-1", "page-2", "top" ], rows["under"], "the tree is the document's: a page's row is in a list inside its parent's item, and one with no parent here at the top"
    assert_equal [ [ "CANVAS", "page", "-", "true" ] ] * 4 + [ [ "SPAN", "dot", "-", "true" ], [ "SPAN", "bg-surface", "-", "true" ] ] +
                 [ [ "CANVAS", "type", "1", "true" ], [ "SPAN", "truncate", "-", "-" ], [ "CANVAS", "type", "8", "true" ], [ "CANVAS", "type", "retired", "true" ], [ "CANVAS", "type", "all-posts", "true" ] ], rows["marks"],
      "a page's and a post type's mark are the renderer's canvases, each hub saying which it is; a post's dot and a tag's square are CS Studio's own"
    assert_equal [ [ "list.pages(4)", true, "list" ], [ "list.posts(1)", true, "list" ], [ "list.tags(1)", true, "list" ], [ "list.types(4)", true, "list" ] ], rows["lists"], "each group is a list named by its heading"
    assert_equal [ "LABEL", "checkbox", "list.unlisted()" ], rows["checkbox"]
  end

  test "list: a row that is not in view is named with its type and asks to be added, one in view selects, and the checkbox reports its change" do
    result = js_module("mind_graph/node_list", <<~JS)
      (() => {
        const { container, calls, list, read } = #{LIST_SCRIPT}
        document.body.append(container) // a checkbox outside the document changes without saying so
        list.showRows({ heading: "Posts · 3", rows: [ { id: "post-1", title: "Drawn", degree: 3, colour_index: 1, type: "blog" }, { id: "post-2", title: "<b>Absent</b>", degree: 0, colour_index: 1, type: "blog" },
                                                      { id: "post-3", title: "Old", degree: 0, colour_index: null, type: "<i>Gone</i>" } ],
                        inView: (id) => id === "post-1", link: { href: "/posts?type=blog", label: "Open in Posts" } })
        const rows = read()
        const absent = Array.from(container.querySelectorAll("button[data-not-in-view]"), (button) => button.dataset.nodeId)
        container.querySelectorAll("button").forEach((button) => button.click())
        const box = container.querySelector("input[type=checkbox]")
        box.click()
        const link = container.querySelector("a[data-mind-graph-posts-link]")
        const result = { rows, calls, absent, link: [ link.getAttribute("href"), link.textContent ], markup: container.querySelectorAll("b, i").length, checked: box.checked, label: box.closest("label").textContent }
        container.remove()
        return result
      })()
    JS

    assert_equal [ "Posts · 3", [ "Drawn", "3", "", "list.select_post(Drawn,3)" ], [ "<b>Absent</b>", "list.not_in_view()", "", "list.add_post(<b>Absent</b>,blog)" ],
                   [ "Old", "list.not_in_view()", "", "list.add_retired_post(Old,<i>gone</i>)" ] ], result["rows"],
      "the type's label in lower case, and for a retired type its stored name in lower case in its own sentence: never a bare 'post'"
    assert_equal %w[post-2 post-3], result["absent"]
    assert_equal [ [ "select", "post-1" ], [ "add", "post-2" ], [ "add", "post-3" ], [ "unlisted", true ] ], result["calls"]
    assert_equal [ [ "/posts?type=blog", "Open in Posts" ], 0, true, "list.unlisted()" ], result.values_at("link", "markup", "checked", "label")
  end

  # A row is offered as one that adds only while there is a graph to add to:
  # while the graph is being read, or after its read failed, a row that is
  # not in view says so and no more, and a press on it does nothing.
  test "list: without a graph a row that is not in view is named without the add, is marked as doing nothing and asks for nothing, and drawn again with a graph it adds" do
    result = js_module("mind_graph/node_list", <<~JS)
      (() => {
        const { container, calls, list } = #{LIST_SCRIPT}
        document.body.append(container)
        const rows = [ { id: "post-2", title: "Absent", degree: 0, colour_index: 1, type: "blog" }, { id: "post-3", title: "Old", degree: 0, colour_index: null, type: "Gone" } ]
        const read = () => Array.from(container.querySelectorAll("button[data-node-id]"), (button) => [ button.getAttribute("aria-label"), button.hasAttribute("data-not-in-view"), button.getAttribute("aria-disabled") ?? "-", button.lastChild.textContent ])
        list.showRows({ heading: "Posts · 2", rows, inView: () => false, addable: false })
        const without = read()
        container.querySelectorAll("button[data-node-id]").forEach((button) => button.click())
        const pressed = calls.slice()
        list.showRows({ heading: "Posts · 2", rows, inView: () => false })
        const withGraph = read()
        container.querySelectorAll("button[data-node-id]").forEach((button) => button.click())
        container.remove()
        return { without, pressed, withGraph, calls }
      })()
    JS

    assert_equal [ [ "list.absent_post(Absent,blog)", true, "true", "list.not_in_view()" ], [ "list.absent_retired_post(Old,gone)", true, "true", "list.not_in_view()" ] ], result["without"]
    assert_equal [], result["pressed"], "a press asks the app for nothing: not to add, not to select"
    assert_equal [ [ "list.add_post(Absent,blog)", true, "-", "list.not_in_view()" ], [ "list.add_retired_post(Old,gone)", true, "-", "list.not_in_view()" ] ], result["withGraph"]
    assert_equal [ [ "add", "post-2" ], [ "add", "post-3" ] ], result["calls"]
  end

  # Design answer G5: the error line is in the list, with a small button.
  test "list: a failed read says so in the list with Try again, and pressing it asks again" do
    result = js_module("mind_graph/node_list", <<~JS)
      (() => {
        const { container, list } = #{LIST_SCRIPT}
        document.body.append(container)
        let asked = 0
        list.fail("The list couldn't be loaded.", { label: "Try again", onRetry: () => { asked += 1 }, focus: true })
        const button = container.querySelector("[role=alert] button[data-mind-graph-retry]")
        const said = [ container.querySelector("[role=alert] p").textContent, button.textContent, button.type, button.className, document.activeElement === button, container.querySelectorAll("button[data-node-id]").length ]
        button.click()
        button.click()
        const checkbox = Boolean(container.querySelector("input[type=checkbox]"))
        // The rows the retry brought: the button that had the focus is gone, and the first row takes it.
        list.showRows({ heading: "Posts", rows: [ { id: "post-1", title: "One", degree: 0, type: "blog" } ], inView: () => false })
        const focused = document.activeElement?.dataset.nodeId
        container.remove()
        return { said, asked, checkbox, focused }
      })()
    JS

    assert_equal [ "The list couldn't be loaded.", "Try again", "button", "retry", true, 0 ], result["said"]
    assert_equal [ 2, true, "post-1" ], result.values_at("asked", "checkbox", "focused"), "the checkbox above the rows is still there, and the focus goes to the first row once there is one"
  end

  # The keyboard is never left on nothing: the rows are replaced whenever
  # what is in view changes, and a person may be on one of them.
  test "list: rows drawn again keep the focus on the row of the same node, else on the first row, else on the checkbox, and take none from elsewhere" do
    result = js_module("mind_graph/node_list", <<~JS)
      (() => {
        const { container, list } = #{LIST_SCRIPT}
        document.body.append(container)
        const posts = [ { id: "post-1", title: "One", degree: 0, type: "blog" }, { id: "post-2", title: "Two", degree: 0, type: "blog" } ]
        const focused = () => document.activeElement === document.body ? "body" : document.activeElement.dataset.nodeId ?? document.activeElement.type
        const seen = []
        list.showRows({ heading: "Posts", rows: posts, inView: () => false })
        seen.push(focused())                                   // nobody was in the list: nothing takes the focus
        list.row("post-2").focus()
        const before = list.row("post-2")
        list.showRows({ heading: "Posts", rows: posts, inView: () => true })
        seen.push([ focused(), list.row("post-2") !== before ]) // the same node's NEW row
        list.showRows({ heading: "Posts", rows: posts.slice(0, 1), inView: () => true })
        seen.push(focused())                                   // its row is gone: the first row
        list.showRows({ heading: "Posts", rows: [], inView: () => true })
        seen.push(focused())                                   // no row at all: the checkbox
        list.render([ { id: "tag-1", kind: "tag", title: "tag", degree: 2 } ])
        seen.push(focused())                                   // the checkbox is not part of the rows: it keeps the focus
        container.remove()
        return seen
      })()
    JS

    assert_equal [ "body", [ "post-2", true ], "post-1", "checkbox", "checkbox" ], result
  end

  # A viewer who reads no page is told every post is unlisted (the server
  # counts by the pages THEY read), so the filter is not offered to them.
  test "list: without the unlisted read there is no checkbox, and the rows are all there is" do
    result = js_module("mind_graph/node_list", <<~JS)
      (() => {
        const container = document.createElement("div")
        const text = { t: (key) => key, locale: () => "en" }
        const list = m.createList(container, { text, dotClasses: [], unlisted: false, onSelect() {}, onHover() {}, onAdd() {}, onUnlisted() {} })
        list.render([ { id: "tag-1", kind: "tag", title: "tag", degree: 2 } ])
        list.setUnlisted(true)
        return [ container.querySelectorAll("input, label").length, container.querySelectorAll("button[data-node-id]").length ]
      })()
    JS

    assert_equal [ 0, 1 ], result
  end

  # Ruling I1 on Task 7's review: a keyboard or screen-reader user reaches a
  # pill's rows. Each pill has a row in the list, in the pill's own words,
  # under the row of what it hangs off; activating it asks the app for the
  # pill's rows, as a press on the pill does.
  test "list: each pill has a row after the row of what it hangs off, in the pill's own words and named whole, pressing it asks for its rows, and one whose hub has no row stands after the posts" do
    result = js_module("mind_graph/node_list", <<~JS)
      (() => {
        const container = document.createElement("div")
        const calls = []
        const text = { t: (key, values = {}) => `${key.split(".").slice(-2).join(".")}(${Object.values(values).join(",")})`, locale: () => "en" }
        const list = m.createList(container, { text, dotClasses: Array(12).fill("dot"), number: (value) => "n" + value, onSelect: (id) => calls.push([ "select", id ]), onHover: (id) => calls.push([ "hover", id ]),
                                               onAdd() {}, onUnlisted() {}, onMore: (id) => calls.push([ "more", id ]), onBack() {} })
        document.body.append(container)
        const order = () => Array.from(container.querySelectorAll("h2, button[data-node-id]"), (item) => item.tagName === "H2" ? item.textContent : item.dataset.nodeId)
        const nodes = [ { id: "page-1", kind: "page", title: "Blog", degree: 1, depth: 0, order: 0, parent: null }, { id: "post-1", kind: "post", title: "Post", degree: 1, colour_index: 1 },
                        { id: "tag-5", kind: "tag", title: "<b>pill</b>", degree: 6 }, { id: "tag-6", kind: "tag", title: "other", degree: 9 },
                        { id: "type-blog", kind: "type", title: "Blog post", degree: 2, count: 30, colour_index: 1 }, { id: "all-posts", kind: "type", title: "All posts", degree: 1, count: 40, colour_index: null },
                        { id: "more-tag-5", kind: "more", title: "+1 more", count: 1, target: "tag-5", of: "<b>pill</b>" },
                        { id: "more-type-blog", kind: "more", title: "+1,980 more", count: 1980, target: "type-blog", of: "Blog post" } ]
        list.render(nodes)
        const all = order()
        const pill = list.row("more-type-blog")
        const row = [ pill.tagName, pill.type, pill.textContent, pill.getAttribute("aria-label"), pill.hasAttribute("data-more"), pill.hasAttribute("data-not-in-view"), pill.querySelectorAll("b").length,
                      list.row("more-tag-5").getAttribute("aria-label"), container.querySelectorAll("b").length ]
        pill.dispatchEvent(new PointerEvent("pointerover", { bubbles: true }))
        pill.click()
        list.row("type-blog").click()
        // "Post types" is switched off: the hub has no row, the pill is still drawn.
        list.render(nodes.filter((node) => node.kind !== "type"))
        const hubless = order()
        list.render(nodes.filter((node) => node.kind === "more" || node.kind === "page"))
        const postless = order()
        container.remove()
        return { all, row, calls, hubless, postless }
      })()
    JS

    assert_equal [ "list.pages(1)", "page-1", "list.posts(1)", "post-1", "list.tags(2)", "tag-6", "tag-5", "more-tag-5", "list.types(2)", "type-blog", "more-type-blog", "all-posts" ], result["all"],
      "a pill's row follows the row of the hub or the tag it hangs off, and is counted in no heading"
    assert_equal [ "BUTTON", "button", "+1,980 more", "list.more_row(1980,n1980,Blog post,+1,980 more)", true, false, 0, "list.more_row(1,n1,<b>pill</b>,+1 more)", 0 ], result["row"],
      "its visible words are the pill's own, its name says how many posts of what, and a tag's name in it is text"
    assert_equal [ [ "hover", "more-type-blog" ], [ "more", "more-type-blog" ], [ "select", "type-blog" ] ], result["calls"], "hovering it lights the pill, pressing it asks for its rows and selects nothing"
    assert_equal [ "list.pages(1)", "page-1", "list.posts(1)", "post-1", "more-type-blog", "list.tags(2)", "tag-6", "tag-5", "more-tag-5" ], result["hubless"], "a pill whose hub has no row stands at the end of the posts"
    assert_equal [ "list.pages(1)", "page-1", "more-tag-5", "more-type-blog" ], result["postless"], "and with no post drawn either, after the groups: never without a row"
  end

  # Ruling I1, the way back, and M2: a pill's rows stand under a heading that
  # names them, with "Back to the list" on screen; Escape pressed in the rows
  # goes back too; and a pill's read that failed offers the same way back
  # beside "Try again". The rows of "Not listed on any page" have neither:
  # their checkbox is the way back.
  test "list: a pill's rows have a heading with Back to the list, Escape in the rows goes back, a failed read of a pill offers the way back, and the unlisted rows have none" do
    result = js_module("mind_graph/node_list", <<~JS)
      (() => {
        const container = document.createElement("div")
        const calls = []
        const text = { t: (key) => key.split(".").slice(-2).join("."), locale: () => "en" }
        const list = m.createList(container, { text, dotClasses: Array(12).fill("dot"), typeLabels: { blog: "Blog" }, retryClass: "retry", onSelect() {}, onHover() {}, onAdd() {}, onUnlisted() {}, onMore() {} })
        document.body.append(container)
        const back = { label: "Back to the list", onBack: () => calls.push("back") }
        const rows = [ { id: "post-1", title: "One", degree: 0, type: "blog" }, { id: "post-2", title: "Two", degree: 0, type: "blog" } ]
        const key = (target, more = {}) => target.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true, ...more }))
        const stops = () => Array.from(container.querySelectorAll("h2, button, a"), (item) => item.tagName === "H2" ? item.textContent : item.dataset.nodeId ?? item.textContent)

        list.showRows({ heading: "More from Blog · 2", rows, inView: () => false, link: { href: "/posts", label: "Open in Posts" }, back })
        const pill = stops()
        const button = container.querySelector("button[data-mind-graph-back]")
        const control = [ button.type, button.textContent, container.querySelector("section").contains(button), button.compareDocumentPosition(list.row("post-1")) & Node.DOCUMENT_POSITION_FOLLOWING ? "before the rows" : "after" ]
        button.click()
        const unhandled = key(list.row("post-2"))
        key(list.row("post-1"), { ctrlKey: true })
        key(container.querySelector("input[type=checkbox]"))

        list.showRows({ heading: "Posts · 2", rows, inView: () => false })
        const unlisted = stops()
        const kept = key(list.row("post-1"))

        list.row("post-1").focus()
        list.fail("The list couldn't be loaded.", { label: "Try again", onRetry: () => calls.push("retry"), back })
        const failed = [ stops(), document.activeElement?.textContent ]
        key(container.querySelector("[data-mind-graph-retry]"))
        container.querySelector("[role=alert] button[data-mind-graph-back]").click()
        list.fail("The list couldn't be loaded.", { label: "Try again", onRetry() {} })
        const plain = stops()
        list.render([ { id: "tag-1", kind: "tag", title: "tag", degree: 2 } ])
        const groups = key(list.row("tag-1"))
        container.remove()
        return { pill, control, unhandled, unlisted, kept, failed, plain, groups, calls }
      })()
    JS

    assert_equal [ "More from Blog · 2", "Back to the list", "post-1", "post-2", "Open in Posts" ], result["pill"], "the heading, the way back, the rows, then the way to Posts"
    assert_equal [ "button", "Back to the list", true, "before the rows" ], result["control"]
    assert_equal [ "Posts · 2", "post-1", "post-2" ], result["unlisted"], "the rows of the checkbox's filter have no such button"
    assert_equal [ [ "Try again", "Back to the list" ], "Try again" ], result["failed"], "the error line keeps a way back, and the focus that was in the rows is on Try again, not on nothing"
    assert_equal [ "Try again" ], result["plain"], "a failed read of the unlisted posts has Try again alone: its checkbox is the way back"
    assert_equal %w[back back back back], result["calls"], "the button, Escape in a pill's rows, Escape on the error line of a pill's read, and the button there; never Escape with a modifier, on the checkbox, in the unlisted rows or in the groups"
    assert_equal [ false, true, true ], result.values_at("unhandled", "kept", "groups"), "Escape is taken (prevented) only where it goes back"
  end

  # Ruling I2: AFTER A ROW IS ADDED THE FIGURES ARE TRUE. One source: what the
  # page holds. The pill's count falls by one for each of its posts that is
  # drawn, the pill goes at none, and the canvas's name, which reads the
  # pills in view, follows; a post no page lists that was counted as "not
  # shown" is no longer counted so.
  test "graph data: a post added from the list is counted where it was counted before: its pill's figure falls and the pill goes at none, the summary follows, and an unconnected post is no longer one that isn't shown" do
    focus = { kind: "page", node_id: "page-1", title: "Blog", depth: 2 }
    result = page.evaluate_async_script(<<~JS, focus)
      const [ focus, done ] = arguments
      Promise.all([ import("mind_graph/graph_data"), import("mind_graph/summary") ]).then(([ data, { summaryOf } ]) => {
        const text = { t: (key, values = {}) => `${key.split(".").pop()}(${Object.values(values).join(" ")})` }
        const nodes = [ { id: "page-1", kind: "page", listed_count: 23 }, ...Array.from({ length: 20 }, (_, index) => ({ id: `post-${index}`, kind: "post" })), { id: "type-a", kind: "type" }, { id: "tag-9", kind: "tag" },
                        { id: "more-type-a", kind: "more", count: 2, target: "type-a" }, { id: "more-tag-9", kind: "more", count: 1, target: "tag-9" } ]
        const local = { focus, shown: 20, total: 20 }
        const all = { nodes: new Set(data.NODE_TOGGLES), lines: new Set(data.LINE_TOGGLES) }
        const seen = []
        const look = () => {
          const { visibleNodes } = data.visible({ nodes, edges: [], on: all })
          seen.push([ nodes.filter((node) => node.kind === "more").map((pill) => pill.count), visibleNodes.map((index) => nodes[index].id).filter((id) => id.startsWith("more")),
                      summaryOf({ nodes, visibleNodes, lines: 0, data: local, off: { nodes: [], lines: [] }, toggles: 4 }, { text, number: String }) ])
        }
        const add = (row) => { const pill = data.countAdded(nodes, local, row); if (pill >= 0) nodes.push({ id: row.id, kind: "post" }); return pill }
        look()
        const pills = [ add({ id: "post-20", via: "type-a" }) ]
        look()
        pills.push(add({ id: "post-21", via: "type-a" }))
        look()
        pills.push(add({ id: "post-22", via: "tag-9" }))
        look()
        // No pill is left for that target, or the row names none: nothing to count down.
        pills.push(data.countAdded(nodes, local, { id: "post-23", via: "type-a" }), data.countAdded(nodes, local, { id: "post-24", via: "type-zzz" }), data.countAdded(nodes, local, { id: "post-25" }))

        // "N other posts have no connections yet and aren't shown." (the whole graph).
        // "N other posts have no connections yet and aren't shown." (the whole graph). A row of
        // "Not listed on any page" says whether its post is one of them (`unconnected`).
        const lone = (id) => ({ id, unconnected: true })
        const whole = { shown: 5, total: 5, isolated: 2 }
        const capped = { shown: 2000, total: 2040, isolated: 3 }
        const around = { focus, shown: 5, total: 5 }
        const isolated = [ data.countAdded([], whole, lone("post-1")), whole.isolated, data.countAdded([], whole, lone("post-2")), whole.isolated, data.countAdded([], whole, lone("post-3")), whole.isolated,
                           data.countAdded([], capped, { id: "post-4", unconnected: false }), capped.isolated, data.countAdded([], capped, { id: "post-5" }), capped.isolated,
                           data.countAdded([], capped, lone("post-6")), capped.isolated, data.countAdded([], around, lone("post-7")), around.isolated ?? "none" ]
        // "Showing the 2,000 best-connected of 2,040 posts.": a connected post the cut left out is one more shown.
        const cut = { shown: 2000, total: 2040, isolated: 3 }
        const uncut = { shown: 5, total: 5, isolated: 0 }
        const nearby = { focus, shown: 20, total: 40 }
        const shown = [ [ cut, { id: "post-1", unconnected: false } ], [ cut, lone("post-2") ], [ cut, { id: "post-3" } ], [ uncut, { id: "post-4", unconnected: false } ], [ nearby, { id: "post-5", unconnected: false } ] ]
          .map(([ held, row ]) => { data.countAdded([], held, row); return [ held.shown, held.isolated ?? "none" ] })
        // "N of M posts" is of the posts the page lists: one added from "Not listed on any page" is counted beside them.
        const listing = [ { id: "page-1", kind: "page", listed_count: 112 }, ...Array.from({ length: 20 }, (_, index) => ({ id: `post-${index}`, kind: "post", listed: true })), { id: "more-type-a", kind: "more", count: 92, target: "type-a" } ]
        const named = () => summaryOf({ nodes: listing, visibleNodes: listing.map((_, index) => index), lines: 0, data: { focus, shown: 20, total: 20 }, off: { nodes: [], lines: [] }, toggles: 4 }, { text, number: String })
        const before = named()
        // A post the view itself draws that no page lists (a related post) is counted as before.
        listing[1].listed = false
        const drawn = named()
        listing[1].listed = true
        listing.push({ id: "post-900", kind: "post", listed: false, added: true })
        const beside = named()
        done({ seen, pills, isolated, shown, before, beside, drawn })
      }).catch((error) => done({ error: String(error) }))
    JS
    flunk result["error"] if result["error"]

    assert_equal [ [ [ 2, 1 ], %w[more-type-a more-tag-9], "more(3)" ],
                   [ [ 1, 1 ], %w[more-type-a more-tag-9], "more(2)" ],
                   [ [ 0, 1 ], %w[more-tag-9], "more(1)" ],
                   [ [ 0, 0 ], [], "" ] ], result["seen"].map { |counts, pills, summary| [ counts, pills, summary[/more\((\d+) \d+\)/].to_s.sub(/ \d+/, "") ] },
      "each pill counts what is still behind it, one that reaches none is not in view, and the summary says the sum of the pills in view"
    assert_equal [ "posts_of(20 20 23)", "posts_of(21 21 23)", "posts_of(22 22 23)", "posts(23 23 0)" ], result["seen"].map { |_counts, _pills, summary| summary[/posts(?:_of)?\([\d ]+\)/] },
      "N of M: N is the posts drawn, M what the page lists; with every pill gone the page lists no more than is drawn and the plain count is said"
    assert_equal [ 23, 23, 24, -1, -1, -1 ], result["pills"], "which pill was counted down (its index), and none for a row with no pill to count"
    assert_equal [ [ 2001, 3 ], [ 2001, 2 ], [ 2001, 2 ], [ 5, 0 ], [ 20, "none" ] ], result["shown"],
      "at the cap a connected post that is added is one more of those shown, and an unconnected one, and a row that says nothing, are not; with nothing cut, and in a local view, the figure stays"
    assert_match(/posts_of\(20 20 112\)/, result["before"])
    assert_no_match(/ posts\(/, result["before"].sub(/\Alocal\(/, ""), "with every post listed there is no second count")
    assert_match(/posts_of\(20 20 112\).*posts\(1 1\)/, result["beside"], "20 of 112 and 92 more still add up to 112: the unlisted post is counted beside them, and is counted")
    assert_match(/more\(92 92\)/, result["beside"])
    assert_equal result["before"], result["drawn"], "only a post the person added is counted apart: the sentence does not change where nothing was added"
    assert_equal [ -1, 1, -1, 0, -1, 0, -1, 3, -1, 3, -1, 2, -1, "none" ], result["isolated"],
      "a row that says its post has no connection takes one from those that aren't shown, never below none; one the cap cut, and one that says nothing, take none; at the cap an unconnected one still does; a local view counts none"
  end

  # Ruling M5: a tick the worker posted before it took `add` is two numbers
  # short. The page keeps the place it gave the new node until the worker
  # answers for it: no node is ever without a position.
  test "graph data: positions that are short of the page's nodes keep the places the page holds for the rest, and whole ones are taken as they are" do
    result = js_module("mind_graph/graph_data", <<~JS)
      (() => {
        const held = Float32Array.from([ 1, 2, 3, 4, 30, 40 ])
        const short = Float32Array.from([ 10, 20, 11, 21 ])
        const whole = Float32Array.from([ 5, 6, 7, 8, 9, 10 ])
        const merged = m.placedFor(short, held, 3)
        const taken = m.placedFor(whole, held, 3)
        return { merged: Array.from(merged), finite: Array.from(merged).every(Number.isFinite), length: merged.length, same: taken === whole, none: Array.from(m.placedFor(new Float32Array(0), new Float32Array(0), 0)),
                 first: Array.from(m.placedFor(short, new Float32Array(0), 3)) }
      })()
    JS

    assert_equal [ [ 10, 20, 11, 21, 30, 40 ], true, 6, true, [] ], result.values_at("merged", "finite", "length", "same", "none"), "the worker's places for the nodes it knows, the page's own for the one it has not taken yet"
    assert_equal [ 10, 20, 11, 21, 0, 0 ], result["first"], "and where the page holds no place either, the centre: a number, never nothing"
  end

  test "the layout takes one more node with its line after it has come to rest, places it where it is told, and settles again" do
    result = using_wait_time(40) do
      page.evaluate_async_script(<<~JS, ActionController::Base.helpers.asset_path("mind_graph/layout_worker.js"), ActionController::Base.helpers.asset_path("d3-force.js"))
        const [workerUrl, d3Url, done] = arguments
        import("mind_graph/layout_client").then(({ createLayout }) => {
          let last = null
          let first = null
          let afterAdd = null
          const layout = createLayout({
            workerUrl, d3Url,
            onTick: (positions) => { last = Array.from(positions); if (first && !afterAdd && last.length === 6) afterAdd = last },
            onSettled: () => {
              if (!first) { first = last; layout.add({ id: "post-9", radius: 7, x: last[2] + 30, y: last[3] + 30 }, [ { source: "type-blog", target: "post-9", kind: "brings" } ]); layout.add({ id: "post-9", radius: 7, x: 0, y: 0 }, []) }
              else { layout.stop(); done({ first, last, afterAdd }) }
            },
            onError: (message) => done({ error: message })
          })
          layout.start([ { id: "page-1", radius: 9, anchor: true }, { id: "type-blog", radius: 6 } ], [ { source: "page-1", target: "type-blog", kind: "lists" } ], { reducedMotion: true })
        })
      JS
    end

    assert_nil result["error"]
    assert_equal [ 4, 6 ], [ result["first"].size, result["last"].size ], "the second add of the same node added nothing"
    assert_equal [ 0, 0 ], result["last"].first(2)
    assert_operator Math.hypot(result["last"][4] - result["last"][2], result["last"][5] - result["last"][3]), :<, 200, "the added node is joined to the hub that brings it in"
  end

  # d3 throws for a line whose end it does not lay out, and the worker's
  # error would take the whole graph down. The app never sends one (the
  # layout holds every node of the data, whatever the legend hides, so a
  # post's hub is always there); the worker does not rely on that.
  test "the layout takes an added node one of whose lines ends at a node it does not hold, without an error, and keeps its other line" do
    result = using_wait_time(40) do
      page.evaluate_async_script(<<~JS, ActionController::Base.helpers.asset_path("mind_graph/layout_worker.js"), ActionController::Base.helpers.asset_path("d3-force.js"))
        const [workerUrl, d3Url, done] = arguments
        import("mind_graph/layout_client").then(({ createLayout }) => {
          let last = null
          let step = 0
          const layout = createLayout({
            workerUrl, d3Url,
            onTick: (positions) => { last = Array.from(positions) },
            onSettled: () => {
              step += 1
              if (step === 1) {
                layout.add({ id: "post-9", radius: 7, x: 400, y: 400 }, [ { source: "type-gone", target: "post-9", kind: "brings" }, { source: "type-blog", target: "post-9", kind: "brings" } ])
              } else { layout.stop(); done({ far: Math.hypot(last[4] - last[2], last[5] - last[3]), size: last.length }) }
            },
            onError: (message) => done({ error: message })
          })
          // A short, stiff spring for the added line, so that its pull is told from none: the two marks end as near as they may be.
          layout.start([ { id: "page-1", radius: 9, anchor: true }, { id: "type-blog", radius: 6 } ], [ { source: "page-1", target: "type-blog", kind: "lists" } ],
                       { reducedMotion: true, springs: { brings: { distance: 10, strength: 1 } } })
        })
      JS
    end

    assert_nil result["error"]
    assert_equal 6, result["size"]
    assert_operator result["far"], :<, 45, "the line to the hub the layout holds keeps the post beside it"
  end

  # Runs `script` against a layout and answers what happened, in order:
  # "raw:<after>" for each `settled` the WORKER posted and "called" for each
  # `onSettled` the client made of them (for one message the client's handler
  # runs first: it was attached first). The script sets `onCall(count)`, which
  # is told of every `onSettled`, and ends the watch with `finish()`.
  def settled_log(script)
    using_wait_time(30) { settled_log_script(script) }
  end

  def settled_log_script(script)
    page.evaluate_async_script(<<~JS, ActionController::Base.helpers.asset_path("mind_graph/layout_worker.js"), ActionController::Base.helpers.asset_path("d3-force.js"))
      const [workerUrl, d3Url, done] = arguments
      const Real = window.Worker
      let worker = null
      window.Worker = class extends Real { constructor(...args) { super(...args); worker = this } }
      import("mind_graph/layout_client").then(({ createLayout }) => {
        const log = []
        let count = 0
        let onCall = () => {}
        // A task later, so the watch's own listener has logged the message
        // that ended it.
        const finish = () => setTimeout(() => { layout.stop(); window.Worker = Real; done(log) }, 0)
        const layout = createLayout({
          workerUrl, d3Url,
          onTick: () => {},
          onSettled: () => { log.push("called"); count += 1; onCall(count) },
          onError: (message) => { log.push(`error: ${message}`); finish() }
        })
        worker.addEventListener("message", ({ data }) => { if (data.type === "settled") log.push(`raw:${data.after}`) })
        #{script}
      })
    JS
  end

  # Attaches `mind_graph/input` to a canvas made for the test, runs `script`
  # (which has `fire(type, pointerId, x, y, pointerType = "touch")`) and answers the callbacks made,
  # in order, as [name, *arguments]. `target:` is what `onPress` answers: true
  # makes a press the start of a drag, false of a pan.
  def input_calls(script, target: false)
    page.evaluate_async_script(<<~JS, target)
      const [target, done] = arguments
      import("mind_graph/input").then(({ attachInput }) => {
        const canvas = document.createElement("canvas")
        canvas.style.cssText = "position: fixed; left: 0; top: 0; width: 600px; height: 400px; z-index: 1000"
        document.body.append(canvas)
        const calls = []
        const record = (name) => (...args) => { calls.push([name, ...args.map((value) => Math.round(value * 1000) / 1000)]) }
        const detach = attachInput(canvas, {
          onPress: (x, y) => { calls.push(["press", x, y]); return target ? "node" : null },
          onDrag: record("drag"), onDrop: record("drop"), onPan: record("pan"), onClick: record("click"),
          onDoubleClick: record("doubleclick"), onZoom: record("zoom"), onHover: record("hover"), onEscape: record("escape")
        })
        const fire = (type, pointerId, x, y, pointerType = "touch") => canvas.dispatchEvent(new PointerEvent(type, { pointerId, pointerType, isPrimary: pointerId === 1, button: 0, clientX: x, clientY: y, bubbles: true, cancelable: true }))
        const doubleClick = (x, y) => canvas.dispatchEvent(new MouseEvent("dblclick", { clientX: x, clientY: y, bubbles: true, cancelable: true }))
        #{script}
        detach()
        canvas.remove()
        done(calls)
      })
    JS
  end

  # Draws one frame through `mind_graph/renderer` onto a context that only
  # records, on a 200 x 100 canvas with the camera at rest: every position is
  # a live post of degree one (radius 7) -- or, for an index in `tags`, a tag
  # of degree one (half side 4.5) -- and `edges` are pairs of node indexes.
  # `selected` / `hovered` are indexes, `pinned` a list of them; the selected
  # node's neighbours are the nodes its edges reach. Answers:
  # - `lines`: the line segments stroked as [x1, y1, x2, y2];
  # - `arcs`: the centres of the circles drawn; `circles`: the same with radii;
  # - `rects`: the squares put into a path (a tag's ring) as [x, y, w, h];
  # - `strokes`: for each edge pass, its segments flattened (nil for an empty
  #   pass) and the strength it was stroked at;
  # - `nodeAlphas`: the strength each post's mark was filled at, in order;
  # - `ringWidths`: the line widths of the rings.
  NODE_RADIUS = 7
  PIN_RADIUS = 3

  def renderer_calls(positions:, edges:, selected: -1, hovered: -1, pinned: [], tags: [])
    log = page.evaluate_async_script(<<~JS, positions, edges, selected, hovered, pinned, tags)
      const [positions, pairs, selected, hovered, pinned, tags, done] = arguments
      import("mind_graph/renderer").then(({ draw, radiusFor }) => {
        const round = (value) => Math.round(value * 1000) / 1000
        const log = []
        const set = {}
        let from = null
        const context = new Proxy({}, {
          get: (_, name) => {
            if (name === "moveTo") return (x, y) => { from = [x, y] }
            if (name === "lineTo") return (x, y) => { log.push(["line", ...from, x, y]) }
            if (name === "arc") return (x, y, radius) => { log.push(["arc", round(x), round(y), round(radius)]) }
            if (name === "rect") return (...box) => { log.push(["rect", ...box.map(round)]) }
            if (name === "beginPath" || name === "fill" || name === "stroke") return () => { log.push([name, round(set.globalAlpha), set.lineWidth]) }
            return () => {}
          },
          set: (_, name, value) => { set[name] = value; return true }
        })
        const nodes = Array.from({ length: positions.length / 2 }, (_, id) => ({ id, kind: tags.includes(id) ? "tag" : "post", degree: 1, colour_index: 1, status: "live", label: "" }))
        const neighbours = new Set(pairs.flatMap(([source, target]) => (source === selected ? [target] : target === selected ? [source] : [])))
        draw(context, {
          width: 200, height: 100, ratio: 1, camera: { k: 1, tx: 0, ty: 0 },
          theme: { ink: "", meta: "", surface: "", sunken: "", accent: "", categories: Array(6).fill(""), font: "", strongFont: "" },
          nodes, edges: pairs.map(([source, target]) => ({ source, target, kind: "related" })), positions: Float32Array.from(positions),
          radii: nodes.map(radiusFor), widths: nodes.map(() => 0), visibleNodes: nodes.map((_, index) => index), visibleEdges: pairs.map((_, index) => index),
          labels: [], selected, neighbours, focusIndex: -1, hovered, pinned: new Set(pinned)
        })
        done(log)
      }).catch((error) => done({ error: String(error) }))
    JS
    flunk "renderer: #{log["error"]}" if log.is_a?(Hash)

    # Each path -- from one `beginPath` to the next -- with what was done to it.
    paths = log.slice_before { |entry| entry.first == "beginPath" }.map { |entries| entries.drop(1) }
    shape = ->(path) { path.find { |entry| %w[arc rect line].include?(entry.first) } }
    done = ->(path, name) { path.find { |entry| entry.first == name } }
    edge_passes = paths.take_while { |path| shape.call(path).nil? || shape.call(path).first == "line" }
    rings = paths.select { |path| shape.call(path)&.first == "rect" || (shape.call(path)&.first == "arc" && ![ NODE_RADIUS, PIN_RADIUS ].include?(shape.call(path)[3])) }
    {
      "lines" => log.select { |entry| entry.first == "line" }.map { |entry| entry.drop(1) },
      "arcs" => log.select { |entry| entry.first == "arc" }.map { |entry| entry[1, 2] },
      "circles" => log.select { |entry| entry.first == "arc" }.map { |entry| entry.drop(1) },
      "rects" => log.select { |entry| entry.first == "rect" }.map { |entry| entry.drop(1) },
      "strokes" => edge_passes.map { |path| [ path.select { |entry| entry.first == "line" }.flat_map { |entry| entry.drop(1) }.presence, done.call(path, "stroke")[1] ] },
      "nodeAlphas" => paths.select { |path| shape.call(path) == [ "arc", *shape.call(path)&.slice(1, 2), NODE_RADIUS ] }.map { |path| done.call(path, "fill")[1] },
      "ringWidths" => rings.map { |path| done.call(path, "stroke")[2] }
    }
  end

  # Draws `nodes` (posts of degree one unless they say otherwise) at
  # `positions` and answers, in order, every fillText as ["fillText", text],
  # every roundRect as ["roundRect"] and every fill as ["fill", fillStyle,
  # globalAlpha]; `labels` are node indexes drawn at `labelAt`'s place.
  def draw_calls(nodes, positions:, labels:)
    drawn = page.evaluate_async_script(<<~JS, nodes, positions, labels)
      const [given, positions, labelled, done] = arguments
      import("mind_graph/renderer").then(({ draw, radiusFor }) => {
        const log = []
        const set = {}
        const context = new Proxy({}, {
          get: (_, name) => {
            if (name === "fillText") return (text) => { log.push(["fillText", text]) }
            if (name === "roundRect") return () => { log.push(["roundRect"]) }
            if (name === "fill") return () => { log.push(["fill", set.fillStyle, set.globalAlpha]) }
            return () => {}
          },
          set: (_, name, value) => { set[name] = value; return true }
        })
        const nodes = given.map((node, index) => ({ id: `n-${index}`, kind: "post", degree: 1, colour_index: 1, status: "live", ...node }))
        const radii = nodes.map(radiusFor)
        draw(context, {
          width: 400, height: 300, ratio: 1, camera: { k: 1, tx: 0, ty: 0 },
          theme: { ink: "ink", meta: "meta", dim: "dim", warn: "warn", surface: "surface", sunken: "sunken", accent: "accent", line: "line", faint: "faint", page: "page", tree: "tree", radius: 4,
                   categories: [1, 2, 3, 4, 5, 6].map((slot) => `cat-${slot}`), font: "sans", strongFont: "strong", monoFont: "mono", strongMonoFont: "strongMono", countFont: "count" },
          nodes, edges: [], positions: Float32Array.from(positions), radii, widths: nodes.map(() => 0),
          visibleNodes: nodes.map((_, index) => index), visibleEdges: [],
          labels: labelled.map((index) => ({ index, alpha: 1, x: positions[index * 2] + radii[index] + 4, y: positions[index * 2 + 1] })),
          selected: -1, neighbours: new Set(), focusIndex: -1, hovered: -1, pinned: new Set()
        })
        done(log)
      }).catch((error) => done({ error: String(error) }))
    JS
    flunk "renderer: #{drawn["error"]}" if drawn.is_a?(Hash)
    drawn
  end

  # Draws posts of degree one (radius 7), 100 px apart from x = 50 at y = 50,
  # with the given `open_notes` each (nil: the key is absent), then the tags
  # of `tags` (indexes) with `tag_notes`. Answers, in order, each notes badge
  # as ["pill", x, y, width, height, radius, fill], ["line", stroke, width]
  # and ["text", label, x, y, fill, font], and each pin's dot as
  # ["pin", x, y, radius]. The theme's values are their own names.
  def notes_badges(counts, pinned: [], tags: [], tag_notes: nil)
    drawn = page.evaluate_async_script(<<~JS, counts, pinned, tags, tag_notes)
      const [counts, pinned, tags, tagNotes, done] = arguments
      import("mind_graph/renderer").then(({ draw, radiusFor }) => {
        const round = (value) => Math.round(value * 1000) / 1000
        const log = []
        const set = {}
        let badge = null
        const context = new Proxy({}, {
          get: (_, name) => {
            if (name === "beginPath") return () => { badge = null }
            if (name === "roundRect") return (...box) => { badge = box.map(round) }
            if (name === "arc") return (x, y, radius) => { if (radius === #{PIN_RADIUS}) log.push(["pin", round(x), round(y), radius]) }
            if (name === "fill") return () => { if (badge) log.push(["pill", ...badge, set.fillStyle]) }
            if (name === "stroke") return () => { if (badge) log.push(["line", set.strokeStyle, set.lineWidth]) }
            if (name === "fillText") return (label, x, y) => { log.push(["text", label, round(x), round(y), set.fillStyle, set.font]) }
            return () => {}
          },
          set: (_, name, value) => { set[name] = value; return true }
        })
        const nodes = counts.map((count, id) => ({ id, kind: "post", degree: 1, colour_index: 1, status: "live", label: "", ...(count == null ? {} : { open_notes: count }) }))
        tags.forEach((id) => nodes.push({ id, kind: "tag", degree: 1, label: "", open_notes: tagNotes }))
        draw(context, {
          width: 100 * nodes.length, height: 100, ratio: 1, camera: { k: 1, tx: 0, ty: 0 },
          theme: { ink: "ink", meta: "", surface: "surface", sunken: "", accent: "accent", line: "line", categories: Array(6).fill("hue"), font: "", strongFont: "", countFont: "count" },
          nodes, edges: [], positions: Float32Array.from(nodes.flatMap((_, index) => [ 50 + index * 100, 50 ])),
          radii: nodes.map(radiusFor), widths: nodes.map(() => 0), visibleNodes: nodes.map((_, index) => index), visibleEdges: [],
          labels: [], selected: -1, neighbours: new Set(), focusIndex: -1, hovered: -1, pinned: new Set(pinned)
        })
        done(log)
      }).catch((error) => done({ error: String(error) }))
    JS
    flunk "renderer: #{drawn["error"]}" if drawn.is_a?(Hash)
    drawn
  end

  # A canvas context that records (`marks_drawn`, `swatch_drawn`): `log`
  # holds what was filled, stroked and written, each with where it is.
  RECORDING_CONTEXT = <<~'JS'.freeze
    const round = (value) => Math.round(value * 100) / 100
    const log = []
    const set = { dash: [] }
    let shape = null
    const box = (x, y, width, height, ...radius) => [ round(x + width / 2), round(y + height / 2), "box", width, height, ...radius ]
    // A stroked shape by its outer edge: half the line's width more, each way.
    const outer = ([ cx, cy, kind, ...sizes ]) => {
      const half = set.lineWidth / 2
      if (kind === "circle") return [ cx, cy, kind, round(sizes[0] + half) ]
      if (kind === "box") return [ cx, cy, kind, round(sizes[0] + half * 2), round(sizes[1] + half * 2), ...sizes.slice(2).map((radius) => round(radius + half)) ]
      return [ cx, cy, kind ]
    }
    const context = new Proxy({}, {
      get: (_, name) => {
        if (name === "beginPath") return () => { shape = null }
        if (name === "arc") return (x, y, radius) => { shape = [round(x), round(y), "circle", round(radius)] }
        if (name === "rect") return (x, y, width, height) => { shape = box(x, y, width, height) }
        if (name === "roundRect") return (x, y, width, height, radius) => { shape = box(x, y, width, height, radius) }
        if (name === "moveTo") return (x, y) => { shape = [round(x), round(y), "line"] }
        if (name === "setLineDash") return (dash) => { set.dash = dash }
        if (name === "setTransform") return (scale) => { set.scale = scale }
        if (name === "fillRect") return (x, y, width, height) => { const [ cx, cy, ...rest ] = box(x, y, width, height); log.push([cx, cy, "fill", ...rest, set.fillStyle]) }
        if (name === "strokeRect") return (x, y, width, height) => { const [ cx, cy, ...rest ] = outer(box(x, y, width, height)); log.push([cx, cy, "stroke", ...rest, set.strokeStyle, set.lineWidth, set.dash]) }
        if (name === "fillText") return (words, x, y) => { log.push([round(x), round(y), "text", words, set.font, set.fillStyle]) }
        if (name === "fill") return () => { if (shape) log.push([shape[0], shape[1], "fill", ...shape.slice(2), set.fillStyle]) }
        if (name === "stroke") return () => { if (shape) { const [ cx, cy, ...rest ] = outer(shape); log.push([cx, cy, "stroke", ...rest, set.strokeStyle, set.lineWidth, set.dash]) } }
        return () => {}
      },
      set: (_, name, value) => { set[name] = value; return true }
    })
  JS

  # Draws the given nodes 100 pixels apart (the first at 50, 50) against a
  # context that records, with a theme whose values are their own names, and
  # answers per node what was filled, stroked and written, in order:
  # `[ "fill", shape, sizes…, colour ]`, `[ "stroke", shape, sizes…, colour,
  # width, dash ]` and `[ "text", words, font, colour ]`, where a circle's
  # size is its radius, a box's its width, height and (rounded) its corner
  # radius, and a line has none. A STROKE'S SIZE IS ITS OUTER SIZE, the
  # path's plus half the line's width each way: what a person sees of it,
  # and what the design gives ("14 by 10", "radius 7"). So an outline drawn
  # inside its mark's edge reads as the mark's own size, and one centred on
  # the edge as three quarters of a pixel more. `places: true` puts where the part is in
  # front of each -- its centre from the node's centre, x then y (a line's:
  # where it starts). `labels: true` draws every node's label; `selected`,
  # `hovered` and `pinned` are indexes.
  def marks_drawn(nodes, places: false, labels: false, selected: -1, hovered: -1, pinned: [], round_rect: true)
    drawn = page.evaluate_async_script(<<~JS, nodes, labels, selected, hovered, pinned, round_rect)
      const [given, labelled, selected, hovered, pinned, roundRect, done] = arguments
      import("mind_graph/renderer").then(({ draw, radiusFor }) => {
        #{RECORDING_CONTEXT}
        // A browser whose canvas has no roundRect (it is newer than the rest).
        const surface = roundRect ? context : new Proxy(context, { get: (target, name) => (name === "roundRect" ? undefined : target[name]), set: (target, name, value) => { target[name] = value; return true } })
        const nodes = given.map((node, index) => ({ id: `n-${index}`, kind: "post", degree: 1, colour_index: 1, status: "live", label: "", ...node }))
        const positions = Float32Array.from(nodes.flatMap((_, index) => [ 50 + index * 100, 50 ]))
        const radii = nodes.map(radiusFor)
        draw(surface, {
          width: 100 * nodes.length, height: 100, ratio: 1, camera: { k: 1, tx: 0, ty: 0 },
          theme: { ink: "ink", meta: "meta", dim: "dim", warn: "warn", surface: "surface", sunken: "sunken", accent: "accent", line: "line", faint: "faint", page: "page", tree: "tree", radius: 4,
                   categories: [1, 2, 3, 4, 5, 6].map((slot) => `cat-${slot}`), font: "sans", strongFont: "strong", monoFont: "mono", strongMonoFont: "strongMono", countFont: "count" },
          nodes, edges: [], positions,
          radii, widths: nodes.map(() => 0), visibleNodes: nodes.map((_, index) => index), visibleEdges: [],
          // A label 20px right of its mark's centre, on the node's own line.
          labels: labelled ? nodes.map((_, index) => ({ index, alpha: 1, x: 70 + index * 100, y: 50, ...(index === hovered ? { hover: true } : {}) })) : [],
          selected, neighbours: new Set(), focusIndex: -1, hovered, pinned: new Set(pinned)
        })
        done(log)
      }).catch((error) => done({ error: String(error) }))
    JS
    flunk "renderer: #{drawn["error"]}" if drawn.is_a?(Hash)
    by_node = drawn.group_by { |x, *| (x / 100).floor }
    nodes.each_index.map do |index|
      by_node.fetch(index, []).map { |x, y, *rest| places ? [ (x - 50 - index * 100).to_f.round(2), (y - 50).to_f.round(2), *rest ] : rest }
    end
  end

  # The shapes a frame puts into a path or draws at once, per node, whatever
  # is then done with them: `[ "circle", dx, dy, radius ]` and `[ "box", dx,
  # dy, width, height, (corner radius) ]`, each from the node's centre (a
  # box's by its own centre). For what hangs on a mark and rings it.
  def shapes_drawn(nodes, **state)
    marks_drawn(nodes, places: true, **state).map do |drawn|
      drawn.filter_map do |dx, dy, _done, shape, *rest|
        sizes = rest.take_while { |value| value.is_a?(Numeric) }
        [ shape, dx, dy, *sizes ] if %w[circle box].include?(shape)
      end.uniq
    end
  end

  # One frame of three tags with a line of each given kind from the first to
  # the second: each stroked pass that holds a line, as `[colour, width,
  # dash, strength, cap]`, in the order drawn.
  def lines_drawn(kinds, k: 1, selected: -1)
    drawn = page.evaluate_async_script(<<~JS, kinds, k, selected)
      const [kinds, k, selected, done] = arguments
      import("mind_graph/renderer").then(({ draw, radiusFor }) => {
        const log = []
        const set = { dash: [] }
        let lines = 0
        const context = new Proxy({}, {
          get: (_, name) => {
            if (name === "beginPath") return () => { lines = 0 }
            if (name === "lineTo") return () => { lines += 1 }
            if (name === "setLineDash") return (dash) => { set.dash = dash }
            if (name === "stroke") return () => { if (lines) log.push([set.strokeStyle, set.lineWidth, set.dash, Math.round(set.globalAlpha * 1000) / 1000, set.lineCap]); lines = 0 }
            return () => {}
          },
          set: (_, name, value) => { set[name] = value; return true }
        })
        const nodes = [0, 1, 2].map((id) => ({ id, kind: "tag", degree: 1, label: "" }))
        draw(context, {
          width: 400, height: 100, ratio: 1, camera: { k, tx: 0, ty: 0 },
          theme: { ink: "ink", meta: "meta", dim: "dim", warn: "warn", surface: "surface", sunken: "sunken", accent: "accent", line: "line", faint: "faint", page: "page", tree: "tree", radius: 4, categories: Array(6).fill("hue"), font: "", strongFont: "", monoFont: "" },
          nodes, edges: kinds.map((kind) => ({ source: 0, target: 1, kind })), positions: Float32Array.from([ 10 / k, 10 / k, 60 / k, 10 / k, 300 / k, 80 / k ]),
          radii: nodes.map(radiusFor), widths: [0, 0, 0], visibleNodes: [0, 1, 2], visibleEdges: kinds.map((_, index) => index),
          labels: [], selected, neighbours: new Set(selected === 0 ? [1] : []), focusIndex: -1, hovered: -1, pinned: new Set()
        })
        done(log)
      }).catch((error) => done({ error: String(error) }))
    JS
    flunk "renderer: #{drawn["error"]}" if drawn.is_a?(Hash)
    drawn
  end

  # What the swatch called `name` draws, at its size in the page
  # (`SwatchComponent::SIZES`), against the recording context and the theme
  # of `marks_drawn`: each part as `[ x, y, "fill" | "stroke" | "text", … ]`.
  def swatch_drawn(name)
    width, height = Admin::MindGraphScreen::SwatchComponent::SIZES.fetch(name.to_sym)
    drawn = page.evaluate_async_script(<<~JS, name, width, height)
      const [name, width, height, done] = arguments
      import("mind_graph/swatches").then(({ drawSwatch }) => {
        #{RECORDING_CONTEXT}
        drawSwatch(context, { ink: "ink", meta: "meta", dim: "dim", warn: "warn", surface: "surface", sunken: "sunken", accent: "accent", line: "line", faint: "faint", page: "page", tree: "tree", radius: 4,
                              categories: [1, 2, 3, 4, 5, 6].map((slot) => `cat-${slot}`), font: "sans", strongFont: "strong", monoFont: "mono", strongMonoFont: "strongMono", countFont: "count" },
          name, { width, height })
        done(log)
      }).catch((error) => done({ error: String(error) }))
    JS
    flunk "swatches: #{drawn["error"]}" if drawn.is_a?(Hash)
    drawn
  end

  # What a row's mark draws (`swatches.js`, `drawRowMark`) against the
  # recording context and the theme of `marks_drawn`: its parts as
  # `swatch_drawn` answers them, the scale the drawing has, and its canvas's
  # size in the page.
  def row_mark_drawn(kind, of)
    drawn = page.evaluate_async_script(<<~JS, kind, of)
      const [kind, of, done] = arguments
      import("mind_graph/swatches").then(({ drawRowMark, ROW_MARKS }) => {
        #{RECORDING_CONTEXT}
        drawRowMark(context, { ink: "ink", meta: "meta", dim: "dim", warn: "warn", surface: "surface", sunken: "sunken", accent: "accent", line: "line", faint: "faint", page: "page", tree: "tree", radius: 4,
                               categories: [1, 2, 3, 4, 5, 6].map((slot) => `cat-${slot}`), font: "sans", strongFont: "strong", monoFont: "mono", strongMonoFont: "strongMono", countFont: "count" },
          { kind, of })
        done({ parts: log, scale: set.scale, width: ROW_MARKS[kind].width, height: ROW_MARKS[kind].height })
      }).catch((error) => done({ error: String(error) }))
    JS
    flunk "swatches: #{drawn["error"]}" if drawn["error"]
    drawn
  end

  # The canvas's name for each given case, in the locale file's words. A
  # case: `nodes`, `visible` (indexes; every node unless given), `lines`,
  # `data`, `off` (nothing unless given), `around_home`, `toggles` (how many
  # kinds the viewer has a toggle for: four unless given).
  def summaries(*cases)
    keys = I18n.t("admin.mind_graph.script.summary").flat_map { |key, value| value.is_a?(Hash) && !value.key?(:other) ? value.keys.map { |inner| "#{key}.#{inner}" } : [ key ] }
    messages = Class.new { include Admin::MessagesHelper }.new.messages_data("mind_graph.script.capped", "mind_graph.script.isolated_only", *keys.map { |key| "mind_graph.script.summary.#{key}" })
    given = cases.map { |one| { visible: one[:nodes].each_index.to_a, off: ALL_ON, around_home: false, toggles: 4 }.merge(one) }
    result = page.evaluate_async_script(<<~JS, messages, given)
      const [json, cases, done] = arguments
      Promise.all([ import("mind_graph/summary"), import("i18n/messages") ]).then(([ { summaryOf }, { messages } ]) => {
        const holder = document.createElement("div")
        holder.setAttribute("data-messages", json)
        const tools = { text: messages(holder), number: (value) => new Intl.NumberFormat("en").format(value) }
        done(cases.map((one) => summaryOf({ nodes: one.nodes, visibleNodes: one.visible, lines: one.lines, data: one.data, off: one.off, toggles: one.toggles, aroundHome: one.around_home }, tools)))
      }).catch((error) => done({ error: String(error) }))
    JS
    flunk "summary: #{result["error"]}" if result.is_a?(Hash)
    result
  end

  # Imports a module of the page's import map and answers `expression`, in
  # which the module is `m`.
  def js_module(path, expression)
    result = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      import(#{path.to_json}).then((m) => done(#{expression})).catch((error) => done({ error: String(error) }))
    JS
    flunk "#{path}: #{result["error"]}" if result.is_a?(Hash) && result.keys == [ "error" ]
    result
  end
end
