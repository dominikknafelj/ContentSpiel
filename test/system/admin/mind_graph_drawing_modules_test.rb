require "application_system_test_case"

# The drawing modules: `marks`, `renderer`, `labels`, `theme` and `swatches`.
class Admin::MindGraphDrawingModulesSystemTest < Admin::MindGraphModulesSystemTestCase
  SOLID = [].freeze

  DASHED = [ 3, 2.5 ].freeze

  # The status table: one rule for a page and a post, and warn
  # means "scheduled". Read from what the renderer
  # asks of the context: a dashed outline cannot be told from a solid one by
  # one pixel. A corner dot is a surface disk (its 1.5px ring) under a dot.
  CORNER = ->(colour) { [ [ "fill", "circle", 4, "surface" ], [ "fill", "circle", 2.5, colour ] ] }

  # THE WHOLE TABLE, kind by state. The design's status table is written here
  # a second time on purpose, in the test's own words, and every mark that
  # has a state is drawn in every one: each of the twenty-five is exactly
  # what the table says, no two are the same drawing, and a draft is DASHED
  # on every mark, so no state rests on colour alone. A sixth state added to
  # `LOOKS` fails here until it is given its row.
  STATES = {
    "live" => { node: { status: "live" }, fill: :own },
    "draft" => { node: { status: "draft" }, fill: "surface", outline: [ "edge", DASHED ] },
    "scheduled" => { node: { status: "scheduled" }, fill: "surface", outline: [ "dim", SOLID ], centre: "warn" },
    "unpublished" => { node: { status: "live", changes: "unpublished" }, fill: :own, corner: "dim" },
    "change_scheduled" => { node: { status: "live", changes: "scheduled" }, fill: :own, corner: "warn" }
  }.freeze

  # `shape` is the mark that carries the state; `ring` what a ring type draws
  # round it first; `edged` the outline a filled post has in its own hue, by
  # its outer edge. Every other outline is INSIDE its mark: an outlined mark
  # is as large as a filled one.
  STATED_MARKS = {
    "page" => { node: { kind: "page" }, shape: [ "box", 14, 10, 4 ], own: "page" },
    "Home" => { node: { kind: "page", home: true }, shape: [ "box", 18, 13, 4 ], own: "page" },
    "filled post" => { node: { colour_index: 3 }, shape: [ "circle", 7 ], own: "cat-3", edged: [ "circle", 7.75 ] },
    "ring post" => { node: { colour_index: 9 }, shape: [ "circle", 4 ], own: "cat-3", ring: [ "circle", 7 ] },
    "retired post" => { node: { colour_index: nil }, shape: [ "circle", 4 ], own: "meta", ring: [ "circle", 7 ], struck: true }
  }.freeze

  # The Lists line is 1.5px with round caps and a dash of
  # 0.1 / 3.5, which is what makes its dots round. A hub's line to what it
  # brings in is the 1px hairline. Each is in its own theme key, whose token
  # carries its strength: the script draws every line at 1.
  LINES = { "tag" => [ "lineTag", 1, [ 4, 3 ], "butt" ], "related" => [ "lineRelated", 1.5, [], "butt" ], "brings" => [ "lineBrings", 1, [], "butt" ],
            "lists" => [ "lineLists", 1.5, [ 0.1, 3.5 ], "round" ], "tree" => [ "lineTree", 1, [], "butt" ] }.freeze
  AT_FULL = ->(styles) { styles.map { |colour, width, dash, cap| [ colour, width, dash, 1, cap ] } }

  # The legend's swatches, its five status looks among them, are the
  # RENDERER'S OWN drawings: each is compared with what the canvas draws for
  # the same node or line, part for part, so a look that changes in
  # `marks.js` changes here too and no key can show one the canvas does not
  # have.
  SWATCH_STATES = { "state-live" => {}, "state-draft" => { status: "draft" }, "state-scheduled" => { status: "scheduled" },
                    "state-live-with-changes" => { changes: "unpublished" }, "state-live-change-scheduled" => { changes: "scheduled" } }.freeze

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

  # The rules say both "labels never overlap" and "the selection, its
  # neighbours and the focus are always labelled"; where two of them overlap,
  # no-overlap wins and the `always` Set's own order decides who keeps the
  # place (`frame.js` puts the selected node in first).
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

  test "marks: a page is a 14 by 10 card, Home 18 by 13, in each of the five looks" do
    live, draft, scheduled, changed, pending, home = marks_drawn([
      { kind: "page" }, { kind: "page", status: "draft" }, { kind: "page", status: "scheduled" },
      { kind: "page", changes: "unpublished" }, { kind: "page", changes: "scheduled" }, { kind: "page", home: true }
    ])

    assert_equal [ [ "fill", "box", 14, 10, 4, "page" ] ], live
    assert_equal [ [ "fill", "box", 14, 10, 4, "surface" ], [ "stroke", "box", 14, 10, 4, "edge", 1.5, DASHED ] ], draft
    assert_equal [ [ "fill", "box", 14, 10, 4, "surface" ], [ "stroke", "box", 14, 10, 4, "dim", 1.5, SOLID ], [ "fill", "circle", 2, "warn" ] ], scheduled
    assert_equal live + CORNER.call("dim"), changed, "unpublished changes: a dim corner dot"
    assert_equal live + CORNER.call("warn"), pending, "a change scheduled: a warn corner dot"
    assert_equal [ [ "fill", "box", 18, 13, 4, "page" ] ], home
  end

  test "marks: a filled post in each of the five looks, a draft dashed in the Draft chip's edge" do
    live, draft, scheduled, changed, pending = marks_drawn([
      {}, { status: "draft" }, { status: "scheduled" }, { changes: "unpublished" }, { changes: "scheduled" }
    ])

    # A live post's own outline is centred on its edge: its outer edge is at 7.75.
    assert_equal [ [ "fill", "circle", 7, "cat-1" ], [ "stroke", "circle", 7.75, "cat-1", 1.5, SOLID ] ], live
    assert_equal [ [ "fill", "circle", 7, "surface" ], [ "stroke", "circle", 7, "edge", 1.5, DASHED ] ], draft
    assert_equal [ [ "fill", "circle", 7, "surface" ], [ "stroke", "circle", 7, "dim", 1.5, SOLID ], [ "fill", "circle", 2, "warn" ] ], scheduled
    assert_equal live + CORNER.call("dim"), changed
    assert_equal live + CORNER.call("warn"), pending
  end

  # Ring types: the type's mark inside a 1.5px ring,
  # so the five looks are a filled post's, drawn at 4/7 of the radius.
  test "marks: a ring type is its type's mark inside a thin ring, in the same five looks, a retired type's has its stroke, and the inner mark is 4/7 rounded to half a pixel" do
    ring = [ [ "fill", "circle", 7, "surface" ], [ "stroke", "circle", 7, "cat-1", 1.5, SOLID ] ]
    live, draft, scheduled, changed, pending, retired, retired_draft = marks_drawn([
      { colour_index: 7 }, { colour_index: 7, status: "draft" }, { colour_index: 7, status: "scheduled" }, { colour_index: 7, changes: "unpublished" },
      { colour_index: 7, changes: "scheduled" }, { colour_index: nil }, { colour_index: nil, status: "draft" }
    ])

    assert_equal ring + [ [ "fill", "circle", 4, "cat-1" ] ], live, "the ring at radius 7 with a filled radius-4 disk"
    assert_equal ring + [ [ "fill", "circle", 4, "surface" ], [ "stroke", "circle", 4, "edge", 1.5, DASHED ] ], draft
    assert_equal ring + [ [ "fill", "circle", 4, "surface" ], [ "stroke", "circle", 4, "dim", 1.5, SOLID ], [ "fill", "circle", 2, "warn" ] ], scheduled
    assert_equal live + CORNER.call("dim"), changed
    assert_equal live + CORNER.call("warn"), pending
    grey = [ [ "fill", "circle", 7, "surface" ], [ "stroke", "circle", 7, "meta", 1.5, SOLID ] ]
    assert_equal grey + [ [ "fill", "circle", 4, "meta" ], [ "stroke", "line", "meta", 1.5, SOLID ] ], retired
    assert_equal grey + [ [ "fill", "circle", 4, "surface" ], [ "stroke", "circle", 4, "edge", 1.5, DASHED ], [ "stroke", "line", "meta", 1.5, SOLID ] ], retired_draft
    # At every size, to the nearest half pixel.
    inner = marks_drawn([ { colour_index: 7, degree: 1 }, { colour_index: 7, degree: 4 }, { colour_index: 7, degree: 9 }, { colour_index: 7, degree: 20 } ]).map { |drawn| [ drawn[0][2], drawn[2][2] ] }
    assert_equal [ [ 7, 4 ], [ 10, 5.5 ], [ 13, 7.5 ], [ 16, 9 ] ], inner
  end

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

  # Where each part is, from the mark's centre, to the hundredth of a pixel:
  # the centre dot in the middle; the corner dot's
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

  # The hub's inner ring; a ring type's
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
    # A tag's square has its outline on its edge, in the tag hue.
    assert_equal [ [ "fill", "box", 9, 9, "surface" ], [ "stroke", "box", 10.5, 10.5, "tag", 1.5, SOLID ] ], tag
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

  test "renderer: each kind of line has its style, one path per style, and below 40 percent zoom a shared tag's is not drawn" do
    kinds = %w[tree lists related tag brings]

    assert_equal AT_FULL.call(LINES.values), lines_drawn(kinds), "in the order they are drawn: a shared tag's first, the tree's on top, each at full strength"
    assert_equal AT_FULL.call(LINES.except("tag").values), lines_drawn(kinds, k: 0.39)
    assert_equal 5, lines_drawn(kinds, k: 0.4).size
    assert_equal 1, lines_drawn(%w[tree tree tree]).size, "three lines of one style are one path"
  end

  test "renderer: a selection brightens its own lines in ink at full strength, half a pixel wider, and keeps each kind's dash and cap" do
    assert_equal LINES.values.map { |_colour, width, dash, cap| [ "ink", width + 0.5, dash, 1, cap ] }, lines_drawn(%w[tree lists related tag brings], selected: 0)
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

  # Every label is in the sans: a page's and a type's in ink, a post's in
  # dim, a tag's in the tag hue; the selected one semibold and in full ink
  # whatever its kind, the hovered one in ink on its backing; and a node
  # without a label (the pill, whose words are inside it) has none drawn,
  # hovered or not.
  test "renderer: a label is ink for a page and a type, dim for a post, the tag hue for a tag, in the sans, full ink when selected or hovered, and the pill has none" do
    nodes = [ { kind: "page", label: "Page" }, { kind: "type", id: "type-a", label: "Type" }, { kind: "post", label: "Post" }, { kind: "tag", label: "Tag" }, { kind: "more", title: "+3 more", label: "" } ]
    labels = ->(**state) { marks_drawn(nodes, labels: true, **state).map { |drawn| drawn.select { |entry| entry.first == "text" && !entry[1].start_with?("+") }.map { |entry| entry.drop(1) } } }

    assert_equal [ [ [ "Page", "sans", "ink" ] ], [ [ "Type", "sans", "ink" ] ], [ [ "Post", "sans", "dim" ] ], [ [ "Tag", "sans", "tag" ] ], [] ], labels.call
    assert_equal [ [ "Post", "strong", "ink" ] ], labels.call(selected: 2)[2]
    assert_equal [ [ "Tag", "strong", "ink" ] ], labels.call(selected: 3)[3], "a selected tag's label is the semibold sans"
    assert_equal [ [ "Tag", "strong", "ink" ] ], labels.call(selected: 3, hovered: 3)[3]
    assert_equal [ [ "Post", "sans", "ink" ] ], labels.call(hovered: 2)[2]
    assert_equal [ [ "Tag", "sans", "ink" ] ], labels.call(hovered: 3)[3]
    assert_equal [], labels.call(hovered: 4)[4], "a hovered pill draws no label and no backing"
    assert_empty marks_drawn(nodes, labels: true, hovered: 4)[4].select { |entry| entry.first == "fill" && entry.last == "sunken" }
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
        const tokens = [ "ink", "meta", "dim", "warn", "surface", "sunken", "accent", "line", "line-strong", "field-line", "cat-1", "cat-2", "cat-3", "cat-4", "cat-5", "cat-6",
                         "graph-page", "graph-tag", "graph-line-tree", "graph-line-lists", "graph-line-related", "graph-line-tag", "graph-line-brings" ]
        tokens.forEach((token) => element.style.setProperty(`--cs-${token}`, `the-${token}`))
        element.style.setProperty("--cs-graph-faded", "0.45")
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
      "line" => "the-line-strong", "page" => "the-graph-page", "edge" => "the-field-line", "tag" => "the-graph-tag",
      "lineTree" => "the-graph-line-tree", "lineLists" => "the-graph-line-lists", "lineRelated" => "the-graph-line-related", "lineTag" => "the-graph-line-tag", "lineBrings" => "the-graph-line-brings",
      "categories" => (1..6).map { |slot| "the-cat-#{slot}" }, "faded" => 0.45,
      "font" => "12px SansFace", "strongFont" => "600 12px SansFace", "countFont" => "500 11px SansFace",
      "radius" => 7
    }, theme)
    assert_kind_of Numeric, theme["faded"], "the fade is a number the canvas takes as its strength"
    assert_empty theme.select { |key, value| key.match?(/mono/i) || value.to_s.include?("MonoFace") }, "the canvas's text is the sans: no key is a mono font"
    # The brand book's rule, held where the canvas's sizes are chosen: no
    # text under 11px in CS Studio, a canvas's own words included.
    theme.select { |key, _| key.match?(/font\z/i) }.each do |key, font|
      assert_operator font[/(\d+(?:\.\d+)?)px/, 1].to_f, :>=, 11, "#{key} is #{font}: CS Studio draws no text under 11px"
    end
  end

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

  # Four steps by the number of connections, a
  # post's a step larger than a tag's, a tag's
  # square the size of its step.
  test "renderer: a node's size is one of four steps by its connections" do
    sizes = ->(kind) { js_module("mind_graph/renderer", "[1, 2, 3, 5, 6, 12, 13, 400].map((degree) => m.radiusFor({ kind: #{kind.to_json}, degree }))") }

    assert_equal [ 7, 7, 10, 10, 13, 13, 16, 16 ], sizes.call("post")
    assert_equal [ 4.5, 4.5, 6, 6, 8.25, 8.25, 10.5, 10.5 ], sizes.call("tag")
  end

  # The states, read from what the renderer asks of
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

  # A post with open notes
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

  # The count is drawn in the page's sans at weight 500 and 11px, as
  # `text-count` sets a count, and measured in that face once it has loaded:
  # "99+", the widest count, fits its pill with 3px of room on either side,
  # one less than `NOTES_BADGE_PAD` (`px-1`), as the badge's geometry is
  # kept: Archivo's "99+" is 19.6px in a 26px pill.
  test "renderer: the notes count is in the sans at 11px and the widest count, 99+, fits its badge" do
    measured = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      Promise.all([ import("mind_graph/theme"), import("mind_graph/marks") ]).then(async ([ { readTheme }, marks ]) => {
        const theme = readTheme(document.body)
        const faces = await document.fonts.load(theme.countFont, "99+")
        const context = document.createElement("canvas").getContext("2d")
        context.font = theme.countFont
        const pill = marks.notesPill({ kind: "post", open_notes: 120 }, 0, 0, 7)
        done({ faces: faces.map((face) => `${face.family.replace(/"/g, "")} ${face.weight}`), font: theme.countFont, family: getComputedStyle(document.body).fontFamily, text: context.measureText("99+").width, pad: marks.NOTES_BADGE_PAD, width: pill.half * 2 })
      }).catch((error) => done({ error: String(error) }))
    JS
    flunk "renderer: #{measured["error"]}" if measured["error"]

    assert_equal "500 11px #{measured["family"]}", measured["font"]
    assert_match(/Archivo/, measured["family"], "the count is the page's sans")
    assert_includes measured["faces"], "Archivo 500", "the count is measured in the face it is drawn in, not a fallback's"
    assert_operator measured["text"] + (measured["pad"] - 1) * 2, :<=, measured["width"], "\"99+\" is #{measured["text"].round(2)}px in #{measured["font"]}, in a #{measured["width"]}px pill"
  end

  # The count badges must not overlap the page
  # cards: on a page's card, Home's too, the badge
  # stands OUTSIDE the card, 2px clear of its left edge, centred on its top
  # edge, and grows leftwards; a post's still reaches 4px over its corner.
  test "renderer: a page's notes badge stands outside its card, on a page and on Home, and a post's is as it was" do
    page_badge, home_badge, post_badge = shapes_drawn([ { kind: "page", open_notes: 120 }, { kind: "page", home: true, open_notes: 12 }, { open_notes: 3 } ])
      .map { |shapes| shapes.find { |shape| shape.first == "box" && shape.last == 7 } }

    assert_equal [ "box", -22, -5, 26, 14, 7 ], page_badge, "99+ on a 14 by 10 card: right edge at -9, 2px left of -7"
    assert_equal [ "box", -21, -6.5, 20, 14, 7 ], home_badge, "12 on Home's 18 by 13 card: right edge at -11"
    assert_operator post_badge[1] + post_badge[3] / 2, :>, -7 * 0.71, "a post's badge still reaches over its corner"
  end

  # A badge that lands on a
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

  # The badge's box is one more box
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

  # The pin's dot is at the top-right and the badge at the top-left, so both
  # can show: on the smallest mark, at one digit, two digits and
  # "99+", the badge's box (with its line) ends left of where the pin's dot
  # (with its ring) begins. A pill centred on the corner would cover half the
  # dot at two digits and all of it at "99+".
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
  # faded one; hovering fades nothing. Drawn with a theme whose `faded` is
  # 0.5, so a strength written into the renderer fails it.
  test "renderer: a selection brightens its edges and fades the rest to the theme's faded strength, and a hover fades nothing" do
    selected = renderer_calls(positions: [ 10, 10, 60, 10, 110, 10, 160, 10 ], edges: [ [ 0, 1 ], [ 2, 3 ] ], selected: 0, faded: 0.5)
    hovered = renderer_calls(positions: [ 10, 10, 60, 10, 110, 10, 160, 10 ], edges: [ [ 0, 1 ], [ 2, 3 ] ], hovered: 0, faded: 0.5)

    assert_equal [ [ [ 110, 10, 160, 10 ], 0.5 ], [ [ 10, 10, 60, 10 ], 1 ] ], selected["strokes"].reject { |lines, _| lines.nil? }
    assert_equal [ 1, 1, 0.5, 0.5 ], selected["nodeAlphas"], "the selected node and its neighbour at full strength, the others at the theme's faded"
    assert_equal [ [ [ 10, 10, 60, 10, 110, 10, 160, 10 ], 1 ] ], hovered["strokes"].reject { |lines, _| lines.nil? }
    assert_equal [ 1, 1, 1, 1 ], hovered["nodeAlphas"]
  end

  test "swatches: the legend's five status looks are the canvas's own drawing of a post in each state, in ink" do
    on_canvas = marks_drawn(SWATCH_STATES.values)

    SWATCH_STATES.each_key.with_index { |name, index| assert_equal in_hue(on_canvas[index], "ink"), swatch_parts(name), name }
    assert_equal 5, SWATCH_STATES.keys.map { |name| swatch_parts(name) }.uniq.size, "no two looks are one drawing"
    assert_equal Admin::MindGraphScreen::LegendComponent::STATES.map { |state| "state-#{state.to_s.dasherize}" }, SWATCH_STATES.keys, "the legend's states, by Publishing::State's names"
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

  # A ROW'S MARK is the renderer's own
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

  private

  def in_hue(drawn, hue) = drawn.map { |part| part.map { |value| value == "cat-1" ? hue : value } }
  def swatch_parts(name) = swatch_drawn(name).map { |_x, _y, *rest| rest }
end
