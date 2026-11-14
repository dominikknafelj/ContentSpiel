require "test_helper"

# `Admin::DiagramDrawingsScreen::ListComponent`: the Draw diagrams screen's
# root, which carries the run's controller with its values and every word
# its script shows, the colour probe, the "can't draw here" notice, the chips
# the script clones for a row's run states, and the list itself (the pages'
# groups, or the empty line).
class Admin::DiagramDrawingsScreen::ListComponentTest < ViewComponent::TestCase
  include ContentHelper

  EN = BlockTypes::Diagram::SAMPLE_SOURCES.fetch("en")
  CONTROLLER = "admin--diagram--draw-all".freeze
  TARGET = "data-#{CONTROLLER}-target".freeze

  setup do
    Current.actor = users(:one)
    @record = create_page(title: "Flows", published: false)
  end
  teardown { Current.reset }

  def diagram
    result = ContentBlocks::Save.call(ContentBlock.new(owner: @record), attributes: { block_type: "diagram" },
      translations: { "en" => { settings: { "source" => EN } } }, actor: users(:one))
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  def list = render_inline(Admin::DiagramDrawingsScreen::ListComponent.new(to_draw: Diagrams::ToDraw.new(actor: users(:one))))

  # A `<template>`'s content as markup: a template's children are its
  # content's, which the page's parsed tree leaves out.
  def template_content(attribute)
    rendered_content[%r{<template[^>]*#{Regexp.escape(attribute)}[^>]*>(.*?)</template>}m, 1] or flunk "no template #{attribute}"
  end

  def root = page.find("[data-controller='#{CONTROLLER}']")

  def served = JSON.parse(root["data-messages"])

  test "the root carries the controller, the renderer's address and the card's colours" do
    diagram
    list

    assert_equal "/#{ContentSpiel::ADMIN_PATH}/diagram-renderer", root["data-#{CONTROLLER}-renderer-url-value"]
    assert_equal Admin::Fields::MermaidField.colour_names, JSON.parse(root["data-#{CONTROLLER}-colours-value"])
    probe = page.find("[#{TARGET}='colourProbe']", visible: :all)
    assert_includes probe[:class], "content-block--diagram"
    assert_equal "true", probe["aria-hidden"]
  end

  test "every word the run shows is served, the card's reused ones included" do
    diagram
    list

    assert_equal "Stop", served.fetch("diagram_drawings.index.stop")
    assert_equal "Stopping…", served.fetch("diagram_drawings.index.stopping")
    assert_equal({ "one" => "%{count} doesn't draw", "other" => "%{count} don't draw" }, served.fetch("diagram_drawings.index.summary.failed"))
    assert_equal "No longer yours to draw, or no longer here.", served.fetch("components.diagram_drawings_screen.row.reasons.gone")
    assert_equal "Being edited by %{name}.", served.fetch("components.diagram_drawings_screen.row.reasons.held")
    assert_equal I18n.t("admin.components.editor_screen.hold_strip.refused.unknown"),
      served.fetch("components.editor_screen.hold_strip.refused.unknown")
    assert_equal I18n.t("admin.components.fields.mermaid_field.too_large"), served.fetch("components.fields.mermaid_field.too_large")
    assert_equal "This drawing can't be shown on the site.", served.fetch("components.diagram_drawings_screen.row.reasons.invalid_drawing")
    assert_equal I18n.t("admin.components.fields.mermaid_field.frame_title"), served.fetch("components.fields.mermaid_field.frame_title")
    assert_equal "This drawing wasn't saved. Try again.", served.fetch("diagram_drawings.index.failed_generic")
    %w[waiting drawing drawn failed skipped].each { |state| assert served.key?("components.diagram_drawings_screen.row.states.#{state}"), state }
  end

  test "the can't-draw-here notice is a warn note, hidden" do
    diagram
    list

    notice = page.find("[#{TARGET}='insecure'][role='note']", visible: :hidden)
    assert_equal "Diagrams are drawn only over HTTPS, or on localhost. Open CS Studio over HTTPS to draw them.", notice.text(:all).strip
  end

  test "the run's chips are templates, one per state the script writes" do
    diagram
    list

    { "waiting" => "Waiting", "drawing" => "Drawing…", "drawn" => "Drawn", "failed" => "Doesn't draw", "skipped" => "Skipped" }.each do |state, word|
      assert page.has_css?("template[#{TARGET}='chip'][data-state='#{state}']", visible: :all), state
      assert_equal word, Nokogiri::HTML5.fragment(template_content(%(data-state="#{state}"))).text.strip
    end
    assert_includes template_content(%(data-state="drawing")), "admin-spinner"
  end

  test "the rows are grouped by page, in one card" do
    diagram
    other = create_page(title: "Other", published: false)
    ContentBlocks::Save.call(ContentBlock.new(owner: other), attributes: { block_type: "diagram" },
      translations: { "en" => { settings: { "source" => EN } } }, actor: users(:one))
    list

    assert_selector ".rounded-card [data-page-id]", count: 2
    assert_selector "[data-draw-row]", count: 2
    assert_no_selector ".admin-empty-state"
  end

  test "with nothing to draw the card holds the empty line" do
    list

    assert_selector ".rounded-card .admin-empty-state",
      text: "Every diagram is drawn. A diagram written outside CS Studio waits here until it is drawn."
    assert_no_selector "[data-draw-row]"
  end
end
