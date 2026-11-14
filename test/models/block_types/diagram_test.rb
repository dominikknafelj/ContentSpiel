require "test_helper"
require_relative "../../support/diagram_fixtures"

# The Diagram block's declaration (Diagram block spec §1): a Mermaid source,
# its drawing and a description, all three translated settings, and the
# caption column; its sample is one flowchart in three languages, each with
# a drawing current for its source.
class BlockTypes::DiagramTest < ActiveSupport::TestCase
  test "diagram is three translated settings and a caption, nothing required, the source never offered to the AI" do
    diagram = BlockTypes.fetch(:diagram)

    assert_equal "Diagram", diagram.label
    assert_equal "diagram", diagram.icon
    assert_equal :code, diagram.family
    assert_equal [ %w[source mermaid], %w[drawing diagram_drawing], %w[description text] ], diagram.fields.map { |field| [ field.name, field.type.to_s ] }
    assert diagram.fields.all?(&:translated?)
    assert diagram.fields.none?(&:required?)
    source, drawing, description = diagram.fields
    assert_equal Diagrams::Source::MAX_CHARACTERS, source.options[:max]
    assert_equal :drawing, source.options[:drawing]
    assert_not source.field_type.translatable, "the source is never offered to an AI provider"
    assert_not drawing.field_type.translatable
    assert_not drawing.field_type.tracked, "the drawing follows its source and is not tracked for translation state"
    assert_equal "Description", description.label
    assert description.help.present?
    assert_equal %w[caption], diagram.uses_columns
    assert_empty diagram.capabilities
    assert_equal Blocks::DiagramComponent, diagram.component
    assert_equal %w[block page svg description caption], diagram.theme_methods
    assert_equal "diagram.css", diagram.stylesheet
  end

  test "its description is translation_required" do
    fields = BlockTypes.fetch(:diagram).fields.index_by(&:name)

    assert fields.fetch("description").translation_required?
    assert_not fields.fetch("source").translation_required?
    assert_not fields.fetch("drawing").translation_required?
  end

  test "the sample is a flowchart in three languages, each with a drawing current for its source as stored, a description and a caption" do
    sample = BlockTypes.fetch(:diagram).sample
    cast = ContentModel::FieldTypes.fetch(:mermaid).cast

    assert_equal({}, sample.settings)
    assert_equal %w[en de es], sample.translations.keys
    sample.translations.each do |locale, values|
      assert_equal %i[source drawing description caption], values.keys, locale
      stored = cast.call(values[:source])
      assert_equal "flowchart", Diagrams::Source.type(stored), locale
      assert_empty Diagrams::Source.refusals(stored), locale
      drawing = Diagrams::Drawing.new(values[:drawing])
      assert drawing.current?(stored), "the #{locale} drawing was not drawn from its source: run RAILS_ENV=test bin/rails diagram:fixtures"
      assert_nil drawing.reason, locale
      assert_equal values[:drawing]["svg"], Diagrams::Drawing.clean(values[:drawing]["svg"]).svg, "the #{locale} drawing is stored cleaned"
      # `from` is the source's digest by construction; that the SVG is the
      # one drawn from this source is held by the fixtures' copy of it
      # (below) and, here, by the source's accDescr standing in the drawing.
      assert_equal stored[/accDescr: (.+)$/, 1], Nokogiri::XML(values[:drawing]["svg"]).at_xpath("//*[local-name()='desc']")&.text, locale
      assert values[:description].present?, locale
      assert values[:caption].present?, locale
    end
    assert_equal [ sample.translations["en"][:description], sample.translations["en"][:caption] ], sample.shows
  end

  test "the fixtures' sample sources are the sample's, so the task draws the sample's drawings from them" do
    cast = ContentModel::FieldTypes.fetch(:mermaid).cast

    assert_equal BlockTypes::Diagram::SAMPLE_SOURCES.keys.map { |locale| "sample_#{locale}" }, DiagramFixtures.samples.keys
    BlockTypes::Diagram::SAMPLE_SOURCES.each do |locale, source|
      assert_equal cast.call(source), cast.call(DiagramFixtures.samples.fetch("sample_#{locale}")), locale
    end
  end

  test "registering the type reads no drawing: the sample's drawings are read when the sample is asked for" do
    original = BlockTypes::Diagram.method(:sample_drawing)
    BlockTypes::Diagram.define_singleton_method(:sample_drawing) { |locale| raise "read the #{locale} drawing" }
    BlockTypes.reset!
    BlockTypes::Diagram.register
    error = assert_raises(RuntimeError) { BlockTypes.fetch(:diagram).sample }
    assert_equal "read the en drawing", error.message
  ensure
    BlockTypes::Diagram.define_singleton_method(:sample_drawing, original)
    Rails.application.reloader.prepare!
  end
end
