require "test_helper"
require_relative "../../support/diagram_fixtures"

class Diagrams::DrawingTest < ActiveSupport::TestCase
  SVG = "http://www.w3.org/2000/svg".freeze
  Result = Diagrams::Drawing::Result

  def clean(svg) = Diagrams::Drawing.clean(svg)

  # A hand-made drawing: the root Mermaid writes, around `body`.
  def drawing(body, root: "")
    %(<svg xmlns="#{SVG}" id="my-svg" viewBox="0 0 200 100" class="flowchart" role="graphics-document document" aria-roledescription="flowchart-v2"#{root}>#{body}</svg>)
  end

  def parsed(svg) = Nokogiri::XML(svg) { |config| config.strict.nonet }

  def fixture(key) = DiagramFixtures::DIR.join("#{key}.svg").read

  def assert_refused(reason, svg, message = nil)
    assert_equal Result.new(svg: nil, reason: reason), clean(svg), message
  end

  # The elements Mermaid writes inside what the sanitizer drops whole.
  DROPPED_SUBTREES = "//*[local-name()='style' or local-name()='filter' or local-name()='linearGradient' or local-name()='symbol' or local-name()='title']"

  CLASS_TOKEN = /\A[A-Za-z][\w-]*\z/

  # A class each type's stylesheet paints by, which the cleaned drawing must keep.
  PAINTED = {
    "flowchart" => "flowchart-link", "sequence" => "messageLine0", "class" => "classDiagram", "state" => "statediagram-state",
    "er" => "relationshipLine", "gantt" => "task", "pie" => "pieCircle"
  }.freeze

  PAINTED.each_key do |key|
    test "each fixture cleans to an svg with no style, fill, stroke, filter, symbol, style attribute or data-*, and keeps its geometry and classes: #{key}" do
      raw = parsed(fixture(key))
      result = clean(fixture(key))
      assert_nil result.reason, "#{key} was refused"
      cleaned = parsed(result.svg)

      assert_equal "svg", cleaned.root.name
      assert_equal SVG, cleaned.root.namespace.href
      assert_empty cleaned.xpath("//*[local-name()='style' or local-name()='symbol' or local-name()='filter' or local-name()='feDropShadow' or local-name()='linearGradient' or local-name()='stop' or local-name()='title']")
      names = cleaned.xpath("//@*").map(&:name)
      assert_empty names & %w[style fill stroke stroke-width stroke-dasharray opacity color font-family filter name fill-rule clip-rule transform-origin role]
      assert_empty names.grep(/\Adata-/)
      assert_empty cleaned.root.attributes.keys & %w[width height style role aria-describedby aria-labelledby]
      assert_equal raw.root["aria-roledescription"], cleaned.root["aria-roledescription"]

      # Geometry: the root's viewBox, and every drawn shape outside what is dropped.
      assert_equal raw.root["viewBox"], cleaned.root["viewBox"]
      dropped = raw.xpath(DROPPED_SUBTREES).flat_map { |node| [ node, *node.xpath(".//*") ] }
      %w[path rect circle line polygon text tspan].each do |name|
        drawn = raw.xpath("//*[local-name()='#{name}']").to_a - dropped
        assert_equal drawn.map { |node| [ node["d"], node["x"], node["points"] ] }, cleaned.xpath("//*[local-name()='#{name}']").map { |node| [ node["d"], node["x"], node["points"] ] }, "#{key}: #{name}"
      end

      # Classes: only tokens that pass the pattern, all of them from the input, the painted ones kept.
      tokens = ->(document) { document.xpath("//@class").flat_map { |attribute| attribute.value.split }.to_set }
      assert tokens.(cleaned).all? { |token| token.match?(CLASS_TOKEN) }
      assert_operator tokens.(cleaned), :subset?, tokens.(raw)
      assert_includes tokens.(cleaned), PAINTED.fetch(key)
      assert_equal raw.root["class"].to_s, cleaned.root["class"].to_s
    end
  end

  test "a cleaned drawing cleans to itself" do
    PAINTED.each_key do |key|
      once = clean(fixture(key)).svg
      assert_equal once, clean(once).svg, key
    end
  end

  test "Mermaid's desc and its text are kept; a drawing with no desc has none" do
    cleaned = parsed(clean(fixture("flowchart")).svg)
    assert_equal parsed(fixture("flowchart")).at_xpath("//*[local-name()='desc']").text, cleaned.at_xpath("//*[local-name()='desc']").text
    assert_nil parsed(clean(drawing(%(<path d="M0 0"/>))).svg).at_xpath("//*[local-name()='desc']")
  end

  test "the output is written from the parse tree" do
    result = clean(drawing(%(<!-- a comment --><rect x='1' y="2" width='3' height="4"/>)))
    assert_nil result.reason
    assert_not_includes result.svg, "comment"
    assert_not_includes result.svg, "x='1'"
    assert_includes result.svg, %(<rect x="1" y="2" width="3" height="4"/>)
    assert result.svg.start_with?(%(<svg xmlns="#{SVG}")), result.svg
  end

  test "text is written as text, escaped, in UTF-8" do
    result = clean(drawing(%(<text x="1"><tspan>Größe &lt;b&gt; &amp; <![CDATA[<i>]]></tspan></text>)))
    assert_includes result.svg, "<tspan>Größe &lt;b&gt; &amp; &lt;i&gt;</tspan>"
    assert_equal Encoding::UTF_8, result.svg.encoding
  end

  test "a refusal for each" do
    {
      not_xml: [ "<svg", "", "not xml", %(<svg xmlns="#{SVG}"><a xlink:href="x"/></svg>), "<svg>\xFF</svg>".b ],
      doctype: [ %(<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">#{drawing("")}), %(<!DOCTYPE svg>#{drawing("")}) ],
      entity: [ %(<!DOCTYPE svg [<!ENTITY x "y">]>#{drawing("<text>&x;</text>")}), drawing("<text>&undeclared;</text>") ],
      processing_instruction: [ %(<?xml-stylesheet href="https://x.test/a.css"?>#{drawing("")}), drawing(%(<g><?php echo 1 ?></g>)) ],
      roots: [ drawing("") + drawing("") ],
      element: [
        drawing("<script>alert(1)</script>"),
        drawing(%(<foreignObject><div xmlns="http://www.w3.org/1999/xhtml">x</div></foreignObject>)),
        drawing(%(<a href="https://x.test"><text>x</text></a>)),
        drawing(%(<image href="https://x.test/a.png"/>)),
        drawing(%(<use href="#a"/>)),
        drawing(%(<animate attributeName="href" to="javascript:alert(1)"/>)),
        drawing(%(<set attributeName="href" to="x"/>)),
        drawing(%(<animateTransform/>)),
        drawing(%(<animateMotion/>)),
        drawing(%(<iframe/>)),
        drawing(%(<defs><style>@import url(https://x.test/a.css);</style></defs>)),
        drawing(%(<g><style>x{}</style></g>)),
        drawing(%(<symbol><script>alert(1)</script></symbol>)),
        drawing(%(<x:script xmlns:x="http://x.test/ns"/>)),
        drawing(%(<desc>hi<path d="M0 0"/><text>x</text></desc>)),
        drawing(%(<desc><title>x</title></desc>)),
        %(<html xmlns="#{SVG}"/>),
        %(<svg viewBox="0 0 1 1"/>)
      ],
      attribute: [
        drawing(%(<rect onload="alert(1)"/>)),
        drawing("", root: %( onload="alert(1)")),
        drawing(%(<rect onClick="alert(1)"/>)),
        drawing(%(<g xml:base="https://x.test/"><path d="M0 0"/></g>)),
        drawing(%(<path xmlns:xlink="http://www.w3.org/1999/xlink" xlink:href="#a"/>)),
        drawing(%(<path href="#a"/>)),
        drawing(%(<rect marker-end="url(#a)"/>)),
        drawing(%(<path aria-label="x"/>)),
        drawing(%(<path dx="1"/>)),
        drawing(%(<rect marker-mid="url(#a)"/>))
      ],
      url: [
        drawing(%(<path marker-end="url(http://x)"/>)),
        drawing(%(<path marker-start="url(#nowhere)"/>)),
        drawing(%(<rect x="url(#a)"/>)),
        drawing(%(<marker id="m"/><path marker-end="URL(#m) "/>)),
        drawing(%(<path id="p" d="M0 0"/><path marker-end="url(#p)"/>)),
        drawing(%(<g id="g"><path d="M0 0"/></g><line marker-mid="url(#g)"/>))
      ],
      value: [
        drawing(%(<rect class="javascript:alert(1)"/>)),
        drawing(%(<rect class="x data:text/html,1"/>)),
        drawing(%(<rect class="a //x.test"/>)),
        drawing(%(<rect id="javascript:alert(1)"/>)),
        drawing(%(<rect x="1;y"/>)),
        drawing(%(<rect x="auto"/>)),
        drawing(%(<g transform="expression(alert(1))"/>)),
        drawing(%(<g transform="translate(a, 1)"/>)),
        drawing(%(<path d="M0 0 x"/>)),
        drawing(%(<path d="M0 0 (1)"/>)),
        drawing(%(<polygon points="1,2 three"/>)),
        drawing(%(<text text-anchor="inherit"/>)),
        drawing(%(<marker orient="sideways"/>)),
        drawing(%(<rect id="a"/><rect id="a"/>)),
        %(<svg xmlns="#{SVG}"/>),
        %(<svg xmlns="#{SVG}" viewBox="0 0 0 10"/>)
      ]
    }.each do |reason, inputs|
      inputs.each { |input| assert_refused reason, input, "#{reason}: #{input}" }
    end
  end

  test "Mermaid's presentation is dropped quietly, and so are a failing class token and the drop shadow's filter" do
    result = clean(drawing(%(<style>.a{fill:red}</style><g><rect class="task width-27.4375" x="1" style="fill:red" fill="red" stroke="blue" filter="url(#diagram-2-drop-shadow)" data-id="n1" data-points="Ly8vLw=="/></g><g class="200"><rect class="200"/></g>), root: %( width="100%" height="10" style="max-width: 200px;" aria-describedby="d" aria-labelledby="t")))
    assert_nil result.reason
    rect = parsed(result.svg).at_xpath("//*[local-name()='rect']")
    assert_equal({ "class" => "task", "x" => "1" }, rect.attributes.transform_values(&:value))
    assert_equal %w[aria-roledescription class id viewBox], parsed(result.svg).root.attributes.keys.sort
    assert_nil parsed(result.svg).xpath("//*[local-name()='rect']")[1]["class"]
  end

  test "a class token failing the pattern is dropped and the element kept" do
    rect = parsed(clean(drawing(%(<rect class="task width-27.4375" x="1"/>))).svg).at_xpath("//*[local-name()='rect']")
    assert_equal "task", rect["class"]
  end

  test "an empty class, or one whose every token fails, is dropped and the element kept" do
    [ %(class=""), %(class="200 width-1.5"), %(class="  ") ].each do |attribute|
      result = clean(drawing(%(<rect #{attribute} x="1"/>)))
      assert_nil result.reason, attribute
      assert_equal({ "x" => "1" }, parsed(result.svg).at_xpath("//*[local-name()='rect']").attributes.transform_values(&:value), attribute)
    end
  end

  test "geometry takes numbers and units, path data its commands, a transform SVG's functions" do
    result = clean(drawing(%(<g transform="translate(10, 20) rotate(-45)scale(1.5e-1)"><rect x="1px" y="-.5em" width="100%" height="2"/><path d="M1e-3,0 L 10 -2 C1 2 3 4 5 6 A 1 1 0 0 1 2 2 Z"/><polygon points="1,2 3,4 5.5,-6"/><text dy="0.35em">x</text></g>)))
    assert_nil result.reason
    assert_includes result.svg, %(transform="translate(10, 20) rotate(-45)scale(1.5e-1)")
  end

  test "a marker reference names a marker, at the start, the middle or the end" do
    result = clean(drawing(%(<marker id="m"><path d="M0 0"/></marker><path d="M0 0" marker-start="url(#m)" marker-mid="url(#m)" marker-end="url(#m)"/>)))
    assert_nil result.reason
    path = parsed(result.svg).xpath("//*[local-name()='path']").last
    assert_equal [ "url(#d-2)" ] * 3, [ path["marker-start"], path["marker-mid"], path["marker-end"] ]
  end

  test "the empty g is dropped, innermost first" do
    cleaned = parsed(clean(drawing(%(<g class="a"><g><g/></g></g><g><path d="M0 0"/></g><g><symbol><path d="M1 1"/></symbol></g>))).svg)
    assert_equal 1, cleaned.xpath("//*[local-name()='g']").size
    assert_equal [ "M0 0" ], cleaned.xpath("//*[local-name()='path']").map { |path| path["d"] }
  end

  test "Mermaid's title is dropped" do
    cleaned = clean(drawing(%(<title id="chart-title-1">Hand title</title><desc id="chart-desc-1">The description</desc><path d="M0 0"/>))).svg
    assert_not_includes cleaned, "Hand title"
    assert_includes cleaned, "The description"
  end

  test "the value lists take what Mermaid writes and nothing else" do
    assert_nil clean(drawing(%(<marker id="m" orient="auto-start-reverse" markerUnits="strokeWidth" markerWidth="8" markerHeight="8" refX="5" refY="5" viewBox="0 0 10 10"><path d="M0 0"/></marker><line x1="0" y1="0" x2="1" y2="1" marker-end="url(#m)" marker-start="url(#m)"/><text text-anchor="middle" dominant-baseline="central" alignment-baseline="middle" font-size="11" font-weight="" font-style="normal" dy="1em">x</text>))).reason
    assert_equal :value, clean(drawing(%(<marker markerUnits="objectBoundingBox"/>))).reason
    assert_equal :value, clean(drawing(%(<text font-size="10;x"/>))).reason
    assert_equal :value, clean(drawing("").sub(%(aria-roledescription="flowchart-v2"), %(aria-roledescription="a b"))).reason
  end

  test "over MAX_BYTES after cleaning is :too_large; over MAX_ELEMENTS is :too_many_elements" do
    long = "x" * (Diagrams::Drawing::MAX_BYTES + 1)
    assert_refused :too_large, drawing(%(<text>#{long}</text>))
    # Within the bytes, past the elements: the root and MAX_ELEMENTS paths.
    assert_refused :too_many_elements, drawing(%(<path d="M0 0"/>) * Diagrams::Drawing::MAX_ELEMENTS)
    assert_nil clean(drawing(%(<path d="M0 0"/>) * (Diagrams::Drawing::MAX_ELEMENTS - 1))).reason
    # Dropped presentation counts for neither.
    assert_nil clean(drawing(%(<style>#{"x" * Diagrams::Drawing::MAX_BYTES}</style><path d="M0 0"/>))).reason
  end

  test "an input far past MAX_BYTES is refused before it is parsed" do
    assert_refused :too_large, drawing(%(<style>#{"x" * (4 * Diagrams::Drawing::MAX_BYTES)}</style>))
  end

  test "ids are renamed d-1, d-2… and every url(#…) and aria reference follows" do
    result = clean(drawing(%(<desc id="chart-desc-x">About</desc><defs><marker id="my-svg_flowchart-v2-pointEnd"><path d="M0 0"/></marker></defs><path id="L_A_B_0" marker-end="url(#my-svg_flowchart-v2-pointEnd)" marker-start="url(#my-svg_flowchart-v2-pointEnd)"/>), root: %( aria-describedby="chart-desc-x")))
    cleaned = parsed(result.svg)
    assert_equal %w[d-1 d-2 d-3 d-4], cleaned.xpath("//@id").map(&:value)
    path = cleaned.at_xpath("//*[local-name()='path'][@marker-end]")
    assert_equal "url(#d-3)", path["marker-end"]
    assert_equal "url(#d-3)", path["marker-start"]

    markup = Diagrams::Drawing.new("svg" => result.svg, "from" => "x").markup(prefix: "diagram-12-de-", title: "A flow", title_id: "diagram-12-de-title")
    root = parsed(markup).root
    assert_equal "diagram-12-de-d-2", root["aria-describedby"]
    assert_equal "About", parsed(markup).at_xpath("//*[@id='diagram-12-de-d-2']").text
    assert_equal "url(#diagram-12-de-d-3)", parsed(markup).at_xpath("//*[local-name()='path'][@marker-end]")["marker-end"]
  end

  test "markup prefixes the ids, writes role, the title as escaped text and width and height from the viewBox" do
    svg = clean(drawing(%(<marker id="m"><path d="M0 0"/></marker><path marker-end="url(#m)"/>), root: "")).svg
    markup = Diagrams::Drawing.new("svg" => svg, "from" => "x").markup(prefix: "diagram-12-de-", title: "<b>&", title_id: "diagram-12-de-title")

    assert_kind_of ActiveSupport::SafeBuffer, markup
    assert_includes markup, %(<title id="diagram-12-de-title">&lt;b&gt;&amp;</title>)
    root = parsed(markup).root
    assert_equal "img", root["role"]
    assert_equal "diagram-12-de-title", root["aria-labelledby"]
    assert_nil root["aria-describedby"]
    assert_equal "200", root["width"]
    assert_equal "100", root["height"]
    assert_equal "0 0 200 100", root["viewBox"]
    assert_equal %w[diagram-12-de-d-1 diagram-12-de-title diagram-12-de-d-2], parsed(markup).xpath("//@id").map(&:value)
    assert_equal "url(#diagram-12-de-d-2)", parsed(markup).at_xpath("//*[@marker-end]")["marker-end"]
    assert_equal "diagram-12-de-title", parsed(markup).root.element_children.first["id"]
  end

  # The public component caches the markup without its title, which is the
  # description and changes on its own, and puts the title in on each read.
  test "markup is the untitled markup with its title put in: the title as escaped text, no parse, and the smallest width three fifths of the natural one" do
    svg = clean(drawing(%(<path d="M0 0"/>), root: "")).svg
    drawing = Diagrams::Drawing.new("svg" => svg, "from" => "x")
    untitled = drawing.untitled_markup(prefix: "diagram-12-de-", title_id: "diagram-12-de-title")

    assert_not_kind_of ActiveSupport::SafeBuffer, untitled
    assert_includes untitled, %(<title id="diagram-12-de-title"/>)
    assert_equal "--diagram-min-width: 120px", parsed(untitled).root["style"], "0.6 of the viewBox's 200"
    titled = with_singleton_override(Diagrams::Drawing, :read, ->(*) { raise "parsed" }) do
      Diagrams::Drawing.with_title(untitled, title: %(<b>"&'), title_id: "diagram-12-de-title")
    end
    assert_kind_of ActiveSupport::SafeBuffer, titled
    assert_equal drawing.markup(prefix: "diagram-12-de-", title: %(<b>"&'), title_id: "diagram-12-de-title"), titled
    assert_equal %(<b>"&'), parsed(titled).at_xpath("//*[local-name()='title']").text
    assert_raises(ArgumentError) { Diagrams::Drawing.with_title(untitled, title: "t", title_id: "diagram-12-de-other") }
  end

  test "markup keeps Mermaid's desc as the description and drops Mermaid's title" do
    raw = fixture("flowchart").sub(%(<desc id=), %(<title id="chart-title-diagram-1">Mermaid's own title</title><desc id=))
    markup = Diagrams::Drawing.new("svg" => clean(raw).svg, "from" => "x").markup(prefix: "diagram-1-en-", title: "The block's description", title_id: "diagram-1-en-title")
    document = parsed(markup)

    titles = document.xpath("//*[local-name()='title']")
    assert_equal [ "The block's description" ], titles.map(&:text)
    desc = document.at_xpath("//*[local-name()='desc']")
    assert_equal desc["id"], document.root["aria-describedby"]
    assert_equal parsed(fixture("flowchart")).at_xpath("//*[local-name()='desc']").text, desc.text
    assert_not_includes markup, "Mermaid's own title"
  end

  test "width and height are the viewBox's, as Floats" do
    drawing = Diagrams::Drawing.new("svg" => clean(fixture("flowchart")).svg, "from" => "x")
    assert_equal 1107.21484375, drawing.width
    assert_equal 219.8243408203125, drawing.height
    assert_includes drawing.markup(prefix: "p-", title: "t", title_id: "p-title"), %(width="1107.215" height="219.824")
  end

  test "a drawing that fails on read has no markup and no size, and says why" do
    drawing = Diagrams::Drawing.new("svg" => drawing(%(<script>alert(1)</script>)), "from" => "x")
    assert_nil drawing.markup(prefix: "p-", title: "t", title_id: "p-title")
    assert_nil drawing.width
    assert_nil drawing.height
    assert_equal :element, drawing.reason

    assert_nil Diagrams::Drawing.new("svg" => nil, "from" => nil).markup(prefix: "p-", title: "t", title_id: "p-title")
    assert_nil Diagrams::Drawing.new("svg" => clean(fixture("pie")).svg, "from" => "x").reason
  end

  test "markup takes only an id-shaped prefix and title id" do
    drawing = Diagrams::Drawing.new("svg" => clean(fixture("pie")).svg, "from" => "x")
    assert_raises(ArgumentError) { drawing.markup(prefix: %(x" onload="), title: "t", title_id: "p-title") }
    assert_raises(ArgumentError) { drawing.markup(prefix: "p-", title: "t", title_id: "a b") }
    assert_raises(ArgumentError) { drawing.markup(prefix: "p-", title: "t", title_id: "a.b") }
    assert_raises(ArgumentError) { drawing.markup(prefix: "pä-", title: "t", title_id: "p-title") }
    assert_raises(ArgumentError) { drawing.markup(prefix: "p-", title: "t", title_id: "p-tïtle") }
    # A title id that one of the drawing's own prefixed ids could be.
    assert_raises(ArgumentError) { drawing.markup(prefix: "p-", title: "t", title_id: "p-d-1") }
    assert_raises(ArgumentError) { drawing.markup(prefix: "p-", title: "t", title_id: "p-desc") }
    assert drawing.markup(prefix: "p-", title: "t", title_id: "p-title")
  end

  test "current? is true only for the source the drawing was made from" do
    source = "flowchart LR\n  A --> B"
    drawing = Diagrams::Drawing.new("svg" => clean(fixture("flowchart")).svg, "from" => Digest::SHA256.hexdigest(source))
    assert_equal Digest::SHA256.hexdigest(source), Diagrams::Drawing.digest(source)
    assert drawing.current?(source)
    assert_not drawing.current?("flowchart LR\n  A --> C")
    assert_not drawing.current?(nil)
    assert_not Diagrams::Drawing.new("svg" => nil, "from" => nil).current?("")
  end
end
