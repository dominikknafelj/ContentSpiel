require "application_system_test_case"

# The input modules: `input`, `camera`, `hit_test`, `card_placement` and `ids`.
class Admin::MindGraphInputModulesSystemTest < Admin::MindGraphModulesSystemTestCase
  # A pinch zooms towards the point between the
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

  # A small graph is zoomed in to fill the box, up to 3 and never further.
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

  # A dot's target is at least 24 px across on screen,
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

  # Where the card stands: 22 px right of the node's edge and
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

  test "ids: a node's id is its kind and its record's id, and only the first dash separates them" do
    assert_equal [ "post-12", "12", "blog", "owner/a-b", "posts" ],
      js_module("mind_graph/ids", '[m.nodeId("post", 12), m.recordId("post-12"), m.recordId("type-blog"), m.recordId("type-owner/a-b"), m.recordId("all-posts")]')
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
end
