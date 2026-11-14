require "application_system_test_case"
require_relative "../support/diagram_fixtures"

# The Diagram block on the public site, as the browser draws it (Diagram
# block spec §4 and §6, the Design System's PublicDiagramBlock): the stored,
# cleaned drawing printed inline with no script of its own, its labels text
# of the page; its colours the theme's tokens, which a scheme switch and a
# strong band re-value on a drawing already stored; and its size, scaled
# down to its column to three fifths of its natural width, then scrolled
# sideways in its own box, never the page.
class DiagramBlockSystemTest < ApplicationSystemTestCase
  SAMPLE = BlockTypes::Diagram::SAMPLE_SOURCES.fetch("en")
  DESCRIPTION = "A flowchart: a draft goes to review, then is published or sent back.".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Guide")
  end

  # A Diagram block saved as the editor's autosave saves it: the source, the
  # drawing the frame made of it (cleaned again by the cast) and a
  # description, which the default language's card sends with its settings.
  def add_diagram(source: SAMPLE, svg: BlockTypes::Diagram.sample_drawing("en")["svg"], **attributes)
    settings = { "source" => source, "drawing" => { "svg" => svg, "from" => DiagramFixtures.sample_from(source) }, "description" => DESCRIPTION }
    result = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "diagram", settings: settings }.merge(attributes),
      translations: { "en" => { caption: "How a page is published" } })
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  def add_strong_section
    result = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "section", settings: { "layout" => "one", "background" => "strong" } })
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  def open_page
    publish_changes(@page)
    visit PublicSite::Urls.new.path_for(@page, "en")
    assert_selector "figure.content-block--diagram svg[role='img']"
  end

  def with_theme(theme)
    page.execute_script("document.documentElement.dataset.theme = arguments[0]", theme)
    yield
  ensure
    page.execute_script("document.documentElement.dataset.theme = 'light'")
  end

  # What a node, an edge and a label of the block's drawing are painted in,
  # and what the diagram's tokens are THERE: a probe span inside the figure
  # reads a band's values where the band re-values them.
  def paint(block)
    page.evaluate_script(<<~JS, "diagram-#{block.id}-en-title")
      (() => {
        const svg = document.getElementById(arguments[0]).closest("svg")
        const figure = svg.closest("figure")
        const token = (name) => { const span = document.createElement("span"); span.style.color = `var(${name})`; figure.append(span); const value = getComputedStyle(span).color; span.remove(); return value }
        const node = svg.querySelector(".node rect")
        const edge = svg.querySelector("path.flowchart-link")
        const label = svg.querySelector("text")
        return {
          nodeFill: getComputedStyle(node).fill, nodeStroke: getComputedStyle(node).stroke,
          edgeStroke: getComputedStyle(edge).stroke, labelFill: getComputedStyle(label).fill,
          fill: token("--th-diagram-fill"), line: token("--th-diagram-line"), edge: token("--th-diagram-edge"), ink: token("--th-diagram-ink"),
          pageInk: token("--th-ink")
        }
      })()
    JS
  end

  test "a public page draws the diagram inline with no script and its labels as text" do
    block = add_diagram
    open_page

    found = page.evaluate_script(<<~JS, "diagram-#{block.id}-en-title")
      (() => {
        const title = document.getElementById(arguments[0])
        const svg = title.closest("svg")
        const figure = svg.closest("figure")
        return {
          inline: svg.parentElement.classList.contains("content-block--diagram__scroll") && svg.namespaceURI === "http://www.w3.org/2000/svg",
          name: title.textContent, labelledBy: svg.getAttribute("aria-labelledby") === title.id,
          labels: [...svg.querySelectorAll("text")].map((text) => text.textContent.trim()).filter(Boolean),
          font: getComputedStyle(svg.querySelector("text")).fontFamily,
          caption: figure.querySelector("figcaption").textContent.trim(),
          scripts: figure.querySelectorAll("script, iframe, foreignObject, [onload], [onclick]").length,
          mermaid: typeof window.mermaid,
          fetched: performance.getEntriesByType("resource").map((entry) => entry.name).filter((name) => /mermaid|diagram-renderer|diagram\\//.test(name)),
          moduleScripts: [...document.querySelectorAll("script[src], link[rel=modulepreload]")].map((tag) => tag.src || tag.href).filter((name) => /mermaid|diagram/.test(name))
        }
      })()
    JS
    assert found["inline"], "the drawing is an svg of the page, in the figure's scroll box"
    assert_equal DESCRIPTION, found["name"]
    assert found["labelledBy"], "the svg is named by its title"
    %w[Draft Review Published approved changes].each { |label| assert_includes found["labels"], label, "#{label} is text of the page" }
    assert_match(/Archivo/, found["font"], "the labels are set in the face the boxes were measured in")
    assert_equal "How a page is published", found["caption"]
    assert_equal 0, found["scripts"], "nothing in the figure can run"
    assert_equal "undefined", found["mermaid"], "Mermaid is not on a public page"
    assert_empty found["fetched"], "the page fetched nothing of the diagram's editor"
    assert_empty found["moduleScripts"], "no diagram module is loaded or preloaded"
    assert_text "Published"
  end

  test "the drawing re-colours with data-theme dark and on a strong band" do
    section = add_strong_section
    banded = add_diagram(section_id: section.id, section_column: 1)
    plain = add_diagram
    open_page
    assert_selector ".content-section--strong figure.content-block--diagram", count: 1

    seen = {}
    %w[light dark].each do |theme|
      with_theme(theme) do
        [ [ :plain, plain ], [ :banded, banded ] ].each do |where, block|
          found = paint(block)
          label = "#{theme}, #{where}"
          assert_equal found["fill"], found["nodeFill"], "#{label}: a node is filled with --th-diagram-fill"
          assert_equal found["line"], found["nodeStroke"], "#{label}: its outline is --th-diagram-line"
          assert_equal found["edge"], found["edgeStroke"], "#{label}: an edge is --th-diagram-edge"
          assert_equal found["ink"], found["labelFill"], "#{label}: a label is --th-diagram-ink"
          seen[[ theme, where ]] = found
        end
        assert_not_equal seen[[ theme, :plain ]]["nodeFill"], seen[[ theme, :banded ]]["nodeFill"], "#{theme}: the strong band re-values the node's fill"
      end
    end
    # The strong band is a dark ground in both schemes, so its labels are the
    # dark page's light ink: they differ from the page's in the light scheme.
    assert_not_equal seen[[ "light", :plain ]]["labelFill"], seen[[ "light", :banded ]]["labelFill"], "light: the strong band re-values the labels"
    assert_equal seen[[ "light", :plain ]]["pageInk"], seen[[ "light", :plain ]]["labelFill"], "on the page a label is the theme's ink"
    %w[nodeFill labelFill edgeStroke].each do |part|
      assert_not_equal seen[[ "light", :plain ]][part], seen[[ "dark", :plain ]][part], "the scheme switch re-colours the stored drawing's #{part}"
    end
  end

  test "a wide diagram scales to its column, then scrolls in its own box at a phone's width, and the page does not scroll sideways" do
    source = DiagramFixtures.sources.fetch("flowchart")
    block = add_diagram(source: source, svg: DiagramFixtures::DIR.join("flowchart.svg").read)
    natural = Diagrams::Drawing.new("svg" => block.reload.translated_settings.dig("en", "drawing", "svg")).width
    open_page

    measure = lambda do
      page.evaluate_script(<<~JS, "diagram-#{block.id}-en-title")
        (() => {
          const svg = document.getElementById(arguments[0]).closest("svg")
          const box = svg.parentElement
          const root = document.documentElement
          return {
            drawn: svg.getBoundingClientRect().width, column: box.clientWidth, scrolls: box.scrollWidth > box.clientWidth,
            pageWide: root.scrollWidth > root.clientWidth,
            stop: box.tabIndex, role: box.getAttribute("role"), label: box.getAttribute("aria-label")
          }
        })()
      JS
    end

    at_window(1400) do
      wide = measure.call
      assert_operator wide["column"], :<, natural, "the column is narrower than the drawing's natural width"
      assert_operator wide["column"], :>=, natural * Diagrams::Drawing::MIN_SCALE, "and wider than its smallest"
      assert_in_delta wide["column"], wide["drawn"], 1, "the drawing scales down to its column"
      assert_not wide["scrolls"], "and its box does not scroll"
      assert_not wide["pageWide"]
      assert_equal [ 0, "group", DESCRIPTION ], wide.values_at("stop", "role", "label"), "the box is a named keyboard stop whether it scrolls or not"
    end

    at_window(390, height: 844) do
      assert_eventually(message: "the column never narrowed to a phone's") { measure.call["column"] < natural * Diagrams::Drawing::MIN_SCALE }
      phone = measure.call
      assert_in_delta natural * Diagrams::Drawing::MIN_SCALE, phone["drawn"], 1, "the drawing keeps three fifths of its natural width"
      assert phone["scrolls"], "and scrolls sideways in its own box"
      assert_not phone["pageWide"], "the page does not scroll sideways"
      assert_equal [ 0, "group", DESCRIPTION ], phone.values_at("stop", "role", "label")

      find(".content-block--diagram__scroll").send_keys(:right)
      assert_eventually(message: "the box never scrolled from the keyboard") do
        page.evaluate_script("document.querySelector('.content-block--diagram__scroll').scrollLeft") > 0
      end
    end
  end
end
