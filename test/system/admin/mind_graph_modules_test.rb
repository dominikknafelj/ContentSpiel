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

  test "the layout worker starts from its asset URL, lays three nodes out and settles" do
    result = page.evaluate_async_script(<<~JS, ActionController::Base.helpers.asset_path("mind_graph/layout_worker.js"), ActionController::Base.helpers.asset_path("d3-force.js"))
      const [workerUrl, d3Url, done] = arguments
      import("mind_graph/layout_client").then(({ createLayout }) => {
        let ticks = 0
        let last = null
        const layout = createLayout({
          workerUrl, d3Url,
          onTick: (positions) => { ticks += 1; last = Array.from(positions) },
          onSettled: () => { layout.stop(); done({ ticks, last }) },
          onError: (message) => done({ error: message })
        })
        layout.start([{ id: 1, radius: 8 }, { id: 2, radius: 8 }, { id: "tag-3", radius: 6 }], [{ source: 1, target: 2 }, { source: 2, target: "tag-3" }])
      })
    JS

    assert_nil result["error"]
    assert_operator result["ticks"], :>, 0
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
        layout.start([{ id: 1, radius: 8 }, { id: 2, radius: 8 }, { id: 3, radius: 6 }], [{ source: 1, target: 2 }, { source: 2, target: 3 }])
        layout.filter([1, 2], [0])
      })
    JS

    assert_nil result["error"]
    assert_equal 6, result["last"].size
  end

  test "a pin sent in the same tick as start holds its node where it was put until unpinned" do
    result = page.evaluate_async_script(<<~JS, ActionController::Base.helpers.asset_path("mind_graph/layout_worker.js"), ActionController::Base.helpers.asset_path("d3-force.js"))
      const [workerUrl, d3Url, done] = arguments
      import("mind_graph/layout_client").then(({ createLayout }) => {
        let ticks = 0
        let pinned = null
        let unpinned = false
        const layout = createLayout({
          workerUrl, d3Url,
          onTick: (positions) => {
            ticks += 1
            if (ticks === 5) { pinned = [positions[0], positions[1]]; unpinned = true; layout.unpin(1) }
          },
          // Two nodes cool down inside the first slice, before the pin is
          // handled: that first "settled" is not the one after the unpin.
          onSettled: () => { if (unpinned) { layout.stop(); done({ pinned }) } },
          onError: (message) => done({ error: message })
        })
        layout.start([{ id: 1, radius: 8 }, { id: 2, radius: 8 }], [{ source: 1, target: 2 }])
        layout.pin(1, 500, -300)
      })
    JS

    assert_nil result["error"]
    assert_in_delta 500, result["pinned"][0], 0.01
    assert_in_delta(-300, result["pinned"][1], 0.01)
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
