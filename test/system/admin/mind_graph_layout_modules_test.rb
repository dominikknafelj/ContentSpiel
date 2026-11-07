require "application_system_test_case"

# The layout's modules (`layout_worker`, `layout_client`, `layout_parameters`).
class Admin::MindGraphLayoutModulesSystemTest < Admin::MindGraphModulesSystemTestCase
  # The pacing: a small graph UNFOLDS. Each message is one tick of
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

  # Reduced motion: the page says so with `start`, and the layout
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

  # Pinning: a dragged node is held under the pointer, STAYS where
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
  # the first layout is still running and there is only `raw:2`. So machine
  # speed decides which of the two comes, and the test does not insist on
  # `raw:1`. The stale case itself is the test above. The end of the watch is
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
  # node, a little nearer with each tick; it is never there in the
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
end
