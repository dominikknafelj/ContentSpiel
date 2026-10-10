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

  test "a filter sent in the same tick as start waits for the d3 import instead of failing" do
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
        layout.filter([1, 2], [0])
      })
    JS

    assert_nil result["error"]
    assert_equal 6, result["last"].size
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
          layout.filter([1], [])
          answer(1) // the first layout cooled down before the filter was taken up
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
    assert_equal %w[start filter drag drop], log["sent"]
    assert_equal %w[raw:1 raw:2 called raw:2 raw:3 raw:4 called raw:4], log["log"]
  end

  # THE WORKER'S HALF, with the real one: `after` counts the messages taken
  # up. A `filter` is sent right behind `start`, and whichever way that race
  # goes on this machine the page hears of ONE settled layout, the filter's.
  # With reduced motion three nodes usually cool down inside the first 12 ms
  # slice, before the filter is handled, and the worker then posts `settled`
  # twice (`raw:1`, `raw:2`); on a slower machine the filter is taken up while
  # the first layout is still running and there is only `raw:2`. (That it is
  # machine speed that decides was found in CI: this test used to insist on
  # `raw:1`. The stale case itself is the test above.) The end of the watch is
  # a message that changes nothing (a drag of a node that isn't there), which
  # the idle worker answers at once: every `settled` before it has arrived by
  # then, so "exactly once" is not a wait.
  test "a filter sent right behind start is settled once, and only when the filter's layout has cooled down" do
    log = settled_log(<<~JS)
      layout.start([{ id: 1, radius: 8 }, { id: 2, radius: 8 }, { id: 3, radius: 6 }], [{ source: 1, target: 2 }, { source: 2, target: 3 }], { reducedMotion: true })
      layout.filter([1, 2], [0])
      onCall = (count) => { if (count === 1) layout.drag("no such node", 0, 0); else finish() }
    JS

    assert_equal 2, log.count("called"), "one for the filter's layout, one for the drag that ended the watch: #{log}"
    first = log.index("called")
    assert_equal "raw:2", log[first + 1], "the page was told of a settled that did not answer the filter: #{log}"
    assert_equal %w[called raw:3], log.last(2), log.inspect
    assert_not_includes log[0...first], "raw:2"
    assert_includes [ [], [ "raw:1" ] ], log[0...first], "something other than the first layout's own settled came before the filter's: #{log}"
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

  test "camera: fit puts every corner inside the padded box and the middle in the middle" do
    result = js_module("mind_graph/camera", <<~JS)
      (() => {
        const box = { minX: -500, minY: -100, maxX: 500, maxY: 100 }
        const c = m.fit(box, 800, 600)
        return { k: c.k, topLeft: m.toScreen(c, box.minX, box.minY), bottomRight: m.toScreen(c, box.maxX, box.maxY), middle: m.toScreen(c, 0, 0) }
      })()
    JS

    assert_in_delta 0.72, result["k"], 0.001
    assert_in_delta 40, result["topLeft"][0], 0.01
    assert_in_delta 760, result["bottomRight"][0], 0.01
    assert_equal [ 400, 300 ], result["middle"].map(&:round)
    assert_operator result["topLeft"][1], :>=, 40
  end

  # Review focus 5: one node, or all nodes at one point.
  test "camera: fitting a single point does not divide by zero or zoom past 1.5" do
    result = js_module("mind_graph/camera", "(() => { const c = m.fit({ minX: 7, minY: 7, maxX: 7, maxY: 7 }, 800, 600); return [c.k, ...m.toScreen(c, 7, 7)] })()")

    assert_equal [ 1.5, 400, 300 ], result
    assert_equal({ "k" => 1, "tx" => 400, "ty" => 300 }, js_module("mind_graph/camera", "m.fit(null, 800, 600)"))
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
          return m.chooseLabels({ order, positions, widths: new Array(n).fill(60), radii: new Array(n).fill(8),
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
      m.chooseLabels({ order: [0, 1, 2], positions: new Float32Array([0, 0, 10, 2, 0, 200]), widths: [80, 80, 80], radii: [8, 8, 8],
        camera: { k: 1, tx: 100, ty: 100 }, width: 1000, height: 1000, always: new Set() }).map((label) => label.index)
    JS

    assert_equal [ 0, 2 ], labelled
  end

  test "labels: the always set is labelled at any zoom, at full strength, and first" do
    labels = js_module("mind_graph/labels", <<~JS)
      m.chooseLabels({ order: [0, 1, 2], positions: new Float32Array([0, 0, 10, 2, 0, 200]), widths: [80, 80, 80], radii: [8, 8, 8],
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
      m.chooseLabels({ order: [0, 1, 2], positions: new Float32Array([0, 0, 10, 2, 0, 200]), widths: [80, 80, 80], radii: [8, 8, 8],
        camera: { k: 1, tx: 100, ty: 100 }, width: 1000, height: 1000, always: new Set([1, 0]) }).map((label) => label.index)
    JS

    assert_equal [ 1, 2 ], labelled
  end

  test "labels: a member of the always set the filter hides (not in the order) gets no label" do
    labelled = js_module("mind_graph/labels", <<~JS)
      m.chooseLabels({ order: [0, 2], positions: new Float32Array([0, 0, 300, 2, 0, 200]), widths: [80, 80, 80], radii: [8, 8, 8],
        camera: { k: 1, tx: 100, ty: 100 }, width: 1000, height: 1000, always: new Set([1]) }).map((label) => label.index)
    JS

    assert_equal [ 0, 2 ], labelled
  end

  test "labels: a node outside the canvas gets no label, and a label sits right of its node" do
    labels = js_module("mind_graph/labels", <<~JS)
      m.chooseLabels({ order: [0, 1], positions: new Float32Array([50, 50, 5000, 50]), widths: [80, 80], radii: [8, 8],
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

    assert_in_delta 0.52, result["k"], 0.001
    assert_in_delta 40, result["top"][1], 0.01
    assert_in_delta 560, result["bottom"][1], 0.01
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
        return m.chooseLabels({ order: Array.from({ length: n }, (_, i) => i), positions, widths: new Array(n).fill(60), radii: new Array(n).fill(8),
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
        return m.chooseLabels({ order: Array.from({ length: n }, (_, i) => i), positions, widths: new Array(n).fill(60), radii: new Array(n).fill(8),
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
      m.chooseLabels({ order: [1, 0, 2], positions: new Float32Array([0, 0, 10, 2, 0, 200]), widths: [80, 80, 80], radii: [8, 8, 8],
        camera: { k: 1, tx: 100, ty: 100 }, width: 1000, height: 1000, always: new Set() }).map((label) => label.index)
    JS

    assert_equal [ 1, 2 ], labelled
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
      [ "pill", 34.96, 37.96, 14, 14, 7, "surface" ], [ "line", "line", 1 ], [ "text", "3", 41.96, 45.46, "ink", "count" ],
      [ "pill", 128.96, 37.96, 20, 14, 7, "surface" ], [ "line", "line", 1 ], [ "text", "12", 138.96, 45.46, "ink", "count" ],
      [ "pill", 222.96, 37.96, 26, 14, 7, "surface" ], [ "line", "line", 1 ], [ "text", "99+", 235.96, 45.46, "ink", "count" ]
    ], drawn.reject { |entry| entry.first == "pin" }
  end

  # The pin's dot is at the top-right and the badge at the top-left, "so both
  # can show" (handoff): on the smallest mark, at one digit, two digits and
  # "99+", the badge's box (with its line) ends left of where the pin's dot
  # (with its ring) begins. A pill centred on the corner covered half the dot
  # at two digits and all of it at "99+".
  test "renderer: a pinned node's notes badge never reaches its pin, whatever the count" do
    drawn = notes_badges([ 1, 12, 120 ], pinned: [ 0, 1, 2 ])
    pills = drawn.select { |entry| entry.first == "pill" }
    pins = drawn.select { |entry| entry.first == "pin" }

    assert_equal [ 3, 3 ], [ pills.size, pins.size ]
    pills.zip(pins).each do |(_, left, _top, width, *), (_, x, _y, radius)|
      badge_right = left + width + 0.5 # half its 1px line
      pin_left = x - radius - 0.75     # half the dot's 1.5px ring
      assert_operator badge_right, :<, pin_left, "the badge (to #{badge_right}) reaches the pin's dot (from #{pin_left})"
    end
    assert_equal [ 14, 20, 26 ], pills.map { |pill| pill[3] }
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
