require "test_helper"

class Admin::MindGraphScreen::LegendComponentTest < ViewComponent::TestCase
  test "lists only the content types it is given, once each, with their names" do
    render_inline(Admin::MindGraphScreen::LegendComponent.new(content_types: %w[resume_entry resume_entry]))

    assert_selector "[data-legend-type]", count: 1
    assert_selector "[data-legend-type=resume_entry] .admin-type-dot", text: ContentTypes.fetch("resume_entry").label
    assert_no_selector "[data-legend-type=blog]"
  end

  test "types come in registry order" do
    render_inline(Admin::MindGraphScreen::LegendComponent.new(content_types: %w[resume_entry blog]))

    assert_equal %w[blog resume_entry], page.all("[data-legend-type]").map { |li| li["data-legend-type"] }
  end

  # A post whose type is no longer registered is
  # a grey ring with a stroke through it, and the legend says so once -- the
  # stored name is not a label, and the type has no colour slot for a dot.
  test "a retired type adds the Retired type entry, drawn with a stroke through it, and gets no dot of its own" do
    render_inline(Admin::MindGraphScreen::LegendComponent.new(content_types: %w[gone/type resume_entry gone/other]))

    assert_selector "[data-legend=retired]", text: "Retired type", count: 1
    assert_selector "[data-legend=retired] canvas[data-swatch=retired]"
    assert_equal %w[resume_entry], page.all("[data-legend-type]").map { |li| li["data-legend-type"] }
    assert_no_text "gone/type"
  end

  test "without a retired type there is no Retired type entry" do
    render_inline(Admin::MindGraphScreen::LegendComponent.new(content_types: %w[blog resume_entry]))

    assert_no_selector "[data-legend=retired]"
  end

  def legend(content_types: %w[blog], pages: true) = render_inline(Admin::MindGraphScreen::LegendComponent.new(content_types: content_types, pages: pages))

  # The legend is the filter (design answers part one §4, F6), and a new
  # visit starts from the defaults (pages decision 8). Firefox puts a
  # form's state back on a reload, so there a toggle switched off would have
  # stayed off (the graph agrees with the checkbox either way: the state is
  # read from it). `autocomplete="off"` is what tells a browser not to
  # (M12). What a browser does with it is not tested here:
  # the suite's browser restores nothing.
  test "every toggle asks the browser not to put its state back on a reload" do
    legend

    assert_selector "[data-mind-graph-legend] input[type=checkbox]", count: 8
    assert_selector "[data-mind-graph-legend] input[type=checkbox][autocomplete=off]", count: 8
  end

  test "the kinds of node and of line are checkboxes in two named groups, all on, each with its name and an empty count" do
    legend

    assert_selector "fieldset[data-legend-group=nodes] legend", text: "Show", visible: :all
    assert_selector "fieldset[data-legend-group=lines] legend", text: "Lines", visible: :all
    assert_equal %w[page post tag type], page.all("fieldset[data-legend-group=nodes] input[type=checkbox][name=mind_graph_nodes]").map { |input| input["value"] }
    assert_equal %w[tree lists related tag], page.all("fieldset[data-legend-group=lines] input[type=checkbox][name=mind_graph_lines]").map { |input| input["value"] }
    assert_equal 8, page.all("input[type=checkbox][checked]").size
    assert_equal [ "Pages", "Posts", "Tags", "Post types", "Tree", "Lists", "Related", "Shares a tag" ], page.all("label[data-legend-toggle]").map { |label| label.text.squish }
    assert_equal [ "Pages", "Shares a tag" ], [ page.first("input[name=mind_graph_nodes]")["data-name"], page.all("input[name=mind_graph_lines]").last["data-name"] ]
    assert_selector "label[data-legend-toggle] [data-legend-count]", count: 8, text: "", visible: :all
    assert_selector "input[data-action='change->admin--mind-graph--graph#filter']", count: 8
    assert_equal 8, page.all("input[type=checkbox]").map { |input| input["id"] }.uniq.size, "each checkbox has an id of its own"
    assert_no_selector "input[type=radio]"
    assert_no_text "Links in text"
  end

  # The swatches are small canvases the graph's own renderer draws
  # (`mind_graph/swatches.js`): no copy of a mark in SVG or CSS.
  test "every toggle and every key has a swatch for the renderer to draw, at its size, and the legend holds no drawing of its own" do
    legend(content_types: %w[blog gone/type])

    names = page.all("[data-mind-graph-legend] canvas[data-swatch]").map { |canvas| canvas["data-swatch"] }
    assert_equal %w[page post tag type line-tree line-lists line-related line-tag retired pinned notes] +
                 %w[state-live state-draft state-scheduled state-live-with-changes state-live-change-scheduled], names
    assert_selector "[data-mind-graph-legend][data-controller='admin--mind-graph--swatches']"
    assert_selector "label[data-legend-toggle=tag] canvas[data-swatch=tag]"
    assert_selector "fieldset[data-legend-group=lines] label[data-legend-toggle=tag] canvas[data-swatch=line-tag][data-width='22'][data-height='8'][width='22'][height='8'][aria-hidden=true]"
    assert_no_selector "svg"
  end

  # Status is not a filter (the third design answers): the five looks are a
  # key that switches nothing, on the legend's row after Key, in the chip's
  # words (H6: one set of words; `test/lib/mind_graph_guards_test.rb` holds
  # them to the chips'), each with the canvas's own drawing of it.
  test "the legend's Status group holds the five looks in the chip's words, each with its canvas swatch, after the keys" do
    legend

    assert_equal %w[show key status], page.all("[data-mind-graph-legend] > [data-legend-section]").map { |section| section["data-legend-section"] }
    assert_selector "[data-legend-section=status] > span#mind-graph-legend-states.text-label:first-child", exact_text: "Status"
    assert_selector "span#mind-graph-legend-states + ul[data-legend-states][aria-labelledby=mind-graph-legend-states]:last-child"
    states = page.all("ul[data-legend-states] > li")
    assert_equal %w[live draft scheduled live_with_changes live_change_scheduled], states.map { |item| item["data-legend-state"] }
    assert_equal Admin::MindGraphScreen::LegendComponent::STATES.map(&:to_s), states.map { |item| item["data-legend-state"] }
    assert_equal [ "Live", "Draft", "Scheduled", "Live, unpublished changes", "Live, change scheduled" ], states.map { |item| item.text.squish }
    Admin::MindGraphScreen::LegendComponent::STATES.each do |state|
      assert_selector "li[data-legend-state=#{state}] canvas[data-swatch]", count: 1
      assert_selector "li[data-legend-state=#{state}] canvas[data-swatch=state-#{state.to_s.dasherize}][data-width='18'][data-height='18'][aria-hidden=true]"
    end
    assert_no_match(/\d/, page.find("[data-legend-section=status]").text, "no date: the day of a scheduled change stands only on a card's chip")
  end

  # The names are `Publishing::State`'s: a sixth state fails here until the
  # legend has a row for it.
  test "the legend has a row for every state a record can be in, and no other" do
    assert_equal Publishing::State::STATES.sort, Admin::MindGraphScreen::LegendComponent::STATES.sort
  end

  # Every control of the legend is a toggle: the keys, the status looks
  # included, are marks with their names, and nothing opens from it.
  test "the legend opens no dialog and has no button" do
    legend

    assert_no_selector "[data-mind-graph-legend] button, [data-mind-graph-legend] a, [data-mind-graph-legend] [aria-haspopup]", visible: :all
    assert_no_selector "[data-mind-graph-legend] dialog, [data-mind-graph-legend] [data-action*='dialog']", visible: :all
    assert_no_selector "ul[data-legend-states] input, ul[data-legend-keys] input", visible: :all
    assert_no_text "Status key"
  end

  # A kind that can be drawn has its toggle and its key, and one that cannot
  # has none (`PostGraph::Kinds`, the one rule). A TAG is drawn for a reader
  # of pages too: one a page's list block names.
  test "a viewer gets the toggles of the kinds they may be shown: of posts alone, of pages alone with the tags pages list, and none who reads neither" do
    toggles = -> { [ "nodes", "lines" ].map { |group| page.all("fieldset[data-legend-group=#{group}] label[data-legend-toggle]").map { |label| label["data-legend-toggle"] } } }

    legend(pages: false)
    assert_equal [ %w[post tag], %w[related tag] ], toggles.call
    assert_no_selector "canvas[data-swatch=page], canvas[data-swatch=type], canvas[data-swatch=line-tree], canvas[data-swatch=line-lists]"

    legend(content_types: [], pages: true)
    assert_equal [ %w[page tag type], %w[tree lists] ], toggles.call
    assert_selector "label[data-legend-toggle=tag] canvas[data-swatch=tag]"
    assert_no_selector "canvas[data-swatch=post], canvas[data-swatch=line-related], canvas[data-swatch=line-tag]"

    legend
    assert_equal [ %w[page post tag type], %w[tree lists related tag] ], toggles.call

    legend(content_types: [], pages: false)
    assert_no_selector "[data-legend-section=show]"
    assert_no_selector "fieldset, input"
  end

  test "the toggles are the one rule's, kind for kind" do
    [ true, false ].product([ true, false ]).each do |pages, posts|
      component = Admin::MindGraphScreen::LegendComponent.new(content_types: posts ? %w[blog] : [], pages: pages)
      assert_equal PostGraph::Kinds.shown(pages: pages, posts: posts), { nodes: component.node_toggles, lines: component.line_toggles }
    end
  end

  # Claude Design's O5: groups a person can see, "Show" over the toggles of
  # both kinds, "Key" over the marks, then "Status" over the five looks. The
  # marks and the looks hold no stop, so the Tab order is the toggles alone.
  test "the legend is three labelled groups: Show over both kinds of toggle, Key over the marks, Status over the looks" do
    legend(content_types: %w[blog])

    assert_selector "[data-mind-graph-legend] > [data-legend-section=show] + [data-legend-section=key] + [data-legend-section=status]:last-child"
    assert_selector "[data-legend-section=show] > span[aria-hidden=true]:first-child", exact_text: "Show"
    assert_selector "[data-legend-section=show] > fieldset[data-legend-group=nodes] + fieldset[data-legend-group=lines]"
    assert_selector "[data-legend-section=key] > span#mind-graph-legend-key:first-child", exact_text: "Key"
    assert_selector "span#mind-graph-legend-key + ul[data-legend-keys][aria-labelledby=mind-graph-legend-key]:last-child"
    assert_selector "[data-legend-section] > span.text-label", count: 3
    assert_no_selector "[aria-label='Legend']"
  end

  # The mark of a node that stays where it was dropped (the round of
  # 2026-10-08): the canvas draws a small ink dot at the node's top-right, and
  # the legend names it.
  test "names the pin mark" do
    legend(content_types: [])

    assert_selector "ul[data-legend-keys] li[data-legend=pinned]", text: "Pinned"
    assert_selector "[data-legend=pinned] canvas[data-swatch=pinned]"
  end

  # A post with open notes: the canvas draws its count in a
  # small badge at the node's top-left, opposite the pin, and the legend
  # names it after the pin.
  test "names the notes badge, last, after the pin" do
    legend(content_types: [])

    assert_selector "ul[data-legend-keys] li[data-legend=pinned] + li:last-child[data-legend=notes]", text: "Open notes"
    assert_selector "[data-legend=notes] canvas[data-swatch=notes]"
  end
end
