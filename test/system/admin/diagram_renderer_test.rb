require "application_system_test_case"
require "ferrum"
require_relative "../../support/diagram_fixtures"

# The Diagram block's renderer frame, driven as the block card drives it: framed
# with `sandbox="allow-scripts"` by `test/support/diagram_host.html`, which
# `DiagramFixtures::HostApp` serves in front of the application in this test's
# server only (it is no route), and spoken to by postMessage alone.
class Admin::DiagramRendererTest < ApplicationSystemTestCase
  setup do
    @application = Capybara.app
    Capybara.app = DiagramFixtures.host_app
    sign_in_via_form(users(:one))
    visit DiagramFixtures::HOST_PATH
    await_js("window.__ready === true", wait: 15, message: "the renderer frame never said it was ready")
  end

  teardown { Capybara.app = @application }

  # In a Chrome of its own: the suite's Cuprite starts Chrome with
  # `--disable-web-security`, under which a parent reads any frame's document
  # and a font needs no CORS, so neither wall could fail there.
  test "the frame's origin is null and its contentDocument is out of reach" do
    browser = Ferrum::Browser.new(headless: true, timeout: 15, process_timeout: 30, browser_options: { "no-sandbox" => nil })
    renderer = DiagramFixtures.open_host(browser, Capybara.current_session.server, DiagramFixtures.session_cookie(users(:one)))

    assert_equal "null", browser.evaluate("window.__origin")
    assert_equal "null", browser.evaluate("window.__frameDocument()")
    assert_equal "null", renderer.evaluate("window.origin")
    assert_equal "blocked", renderer.evaluate("(() => { try { return window.parent.document ? 'reachable' : 'blocked' } catch (error) { return 'blocked' } })()")
    assert_equal "blocked", renderer.evaluate("(() => { try { return document.cookie, localStorage, 'reachable' } catch (error) { return 'blocked' } })()")

    # The four faces came through CORS from the opaque origin, so Mermaid
    # measures its labels in Archivo.
    faces = renderer.evaluate("Array.from(document.fonts).filter((face) => face.family === 'Archivo' && face.status === 'loaded').map((face) => face.weight).sort()")
    assert_equal %w[400 500 600 700], faces
  ensure
    browser&.quit
  end

  test "a flowchart posted to the frame comes back as an svg with no foreignObject" do
    answer = draw("flowchart", DiagramFixtures.sources.fetch("flowchart"))

    assert_nil answer["error"]
    svg = answer.fetch("svg")
    assert svg.start_with?("<svg"), svg[0, 80]
    assert_not_includes svg, "foreignObject"
    assert_equal svg.bytesize, answer["bytes"]
    drawing = Nokogiri::XML(svg) { |config| config.strict.nononet }
    assert_equal drawing.xpath("//*").size, answer["elements"]
    assert_nil answer["raw"], "the raw drawing is the fixture task's alone"

    # Cleaned as the server cleans: Mermaid's own colours and styles are gone.
    assert_empty drawing.xpath("//*[local-name()='style' or local-name()='filter' or local-name()='linearGradient']")
    %w[style fill stroke stroke-width font-family filter width role].each do |name|
      assert_empty drawing.xpath("/*[@#{name}]"), "the root keeps #{name}"
    end
    assert_empty drawing.xpath("//@*[local-name()='style' or local-name()='fill' or local-name()='stroke' or starts-with(local-name(), 'data-')]")
    assert_equal "flowchart-v2", drawing.root["aria-roledescription"]

    assert_equal 1, frame.evaluate("document.querySelectorAll('#diagram > svg').length"), "the frame shows the drawing itself"
  end

  test "a classDef line is refused before Mermaid sees it" do
    count_mermaid_calls

    answer = draw("classdef", "flowchart LR\n  classDef red fill:#f00\n  A --> B:::red")

    assert_equal({ "kind" => "refused", "line" => 2, "rule" => "colours", "word" => "classDef" }, answer["error"].except("message"))
    assert_equal 0, frame.evaluate("window.__mermaidCalls")
  end

  test "a source over the limit is refused as too_long, never drawn" do
    count_mermaid_calls
    source = "flowchart LR\n" + ("  A --> B\n" * 1_000)
    assert_operator source.length, :>, Diagrams::Source::MAX_CHARACTERS

    answer = draw("long", source)

    assert_equal({ "kind" => "too_long", "line" => 0 }, answer["error"].slice("kind", "line"))
    assert_nil answer["svg"]
    assert_equal 0, frame.evaluate("window.__mermaidCalls")
    assert_equal 0, frame.evaluate("document.querySelectorAll('#diagram svg').length")
  end

  test "a %%{init}%% at the end of a line is refused" do
    answer = draw("directive", "flowchart LR\n  A --> B %%{init: {'theme': 'dark'}}%%")

    assert_equal({ "kind" => "refused", "line" => 2, "rule" => "directive", "word" => "%%{" }, answer["error"].except("message"))
  end

  # Each source's first refusal is decided by `Diagrams::Source` in Ruby and
  # by the frame's port of it, and the two agree: the cases are the rules'
  # edges (a word allowed in one type alone, what is skipped before the
  # keyword, whitespace JavaScript reads otherwise, a first word that is the
  # name of an object's property, a length in code points).
  test "the frame decides every line rule as Diagrams::Source does" do
    cases = {
      "class_in_class" => "classDiagram\n  class Page\n  Page <|-- Post",
      "class_in_flowchart" => "flowchart LR\n  A --> B\n  class A red",
      "leading" => "﻿\n\n%% a comment\n  %% another\nmindmap\n  root",
      "no_type" => "%% only\nhello world",
      "front_matter" => "---\nconfig:\n  htmlLabels: true\n---\nflowchart LR\n  A --> B",
      "first_line_directive" => "%%{init: {}}%%\nflowchart LR\n  A --> B",
      "directive_in_capitals" => "flowchart LR\n  A --> B %%{INIT: {}}%%",
      "no_break_space" => "flowchart LR\n click A call alert()\n  A --> B",
      "constructor" => "constructor\n  A --> B",
      "proto_word" => "flowchart LR\n  __proto__ --> B\n  toString --> C",
      "links" => "sequenceDiagram\n  A->>B: hi\n  link A: Docs @ https://example.com",
      "maths" => "flowchart LR\n  A[\"$$x^2$$\"] --> B",
      "crlf" => "flowchart LR\r\n  A --> B\r\n  style A fill:#f00\r\n",
      "code_points" => "flowchart LR\n  A --> B\n%% #{"😀" * 4_980}",
      "over_the_limit" => "flowchart LR\n" + ("  A --> B\n" * 1_000),
      "blank_over_the_limit" => " \n" * 5_001
    }

    cases.each do |key, source|
      ruby = Diagrams::Source.refusals(source).first
      answer = draw(key, source)
      error = answer["error"]

      if ruby
        expected = { "kind" => ruby.rule == :too_long ? "too_long" : "refused", "line" => ruby.line, "rule" => ruby.rule.to_s, "word" => ruby.word }
        assert_equal expected, error&.except("message"), "#{key}: the frame does not refuse as Diagrams::Source does"
      else
        assert(error.nil? || %w[parse type too_large].include?(error["kind"]), "#{key}: Diagrams::Source lets it through, the frame answered #{error.inspect}")
      end
    end
  end

  # A length is counted in code points, as `Diagrams::Source` counts it, and
  # Mermaid's own limit (UTF-16 units) is set past anything that count lets
  # through, so it never draws its stand-in for a source within the limit.
  test "a source of 6,000 emoji is under the limit and is not refused as too_long" do
    source = "flowchart LR\n  A[\"#{"😀" * 6_000}\"] --> B"
    assert_operator source.length, :<=, Diagrams::Source::MAX_CHARACTERS
    assert_operator source.encode("UTF-16LE").bytesize / 2, :>, Diagrams::Source::MAX_CHARACTERS
    assert_empty Diagrams::Source.refusals(source)

    answer = draw("emoji", source)

    assert_not_equal "too_long", answer.dig("error", "kind"), answer["error"].inspect
    assert_nil answer["error"], answer["error"].inspect
    assert_not_includes answer.fetch("svg"), "Maximum text size"
  end

  private

  # The renderer's own browsing context: Chrome lets the driver into it, no
  # page can.
  def frame
    page.driver.browser.frames.find { |candidate| candidate.url.to_s.include?("diagram-renderer") } || flunk("no renderer frame")
  end

  def draw(id, source)
    page.execute_script("window.__draw(arguments[0], arguments[1])", id, source)
    await_js("window.__answers[#{id.to_json}] !== undefined", wait: 15, message: "the frame never answered #{id}")
    page.evaluate_script("window.__answers[#{id.to_json}]")
  end

  # Counts every call into Mermaid's parser and renderer, in the frame.
  def count_mermaid_calls
    frame.execute(<<~JS)
      window.__mermaidCalls = 0
      for (const name of ["parse", "render"]) {
        const original = mermaid[name]
        mermaid[name] = (...args) => { window.__mermaidCalls++; return original.apply(mermaid, args) }
      }
    JS
  end
end
