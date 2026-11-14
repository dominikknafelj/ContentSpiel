require "test_helper"
require_relative "../support/diagram_fixtures"

# The Diagram block's fixture drawings are the vendored Mermaid's own raw
# output (`bin/rails diagram:fixtures`), and the sanitizer is tested against
# them. So every type on the list has one, every sample source is one the line
# rules let through, and the drawings name the Mermaid file they came from:
# after an upgrade of the vendored file, these fail until the task has drawn
# them again and the new drawings have been read against the sanitizer's lists.
class DiagramFixturesTest < ActiveSupport::TestCase
  # Each sample's key -> what Mermaid calls the diagram (`diagramType`).
  KEYS = {
    "flowchart" => "flowchart-v2", "sequence" => "sequence", "class" => "classDiagram",
    "state" => "stateDiagram", "er" => "er", "gantt" => "gantt", "pie" => "pie"
  }.freeze

  test "every allowed type has a fixture" do
    assert_equal Diagrams::Source::MERMAID_TYPES.sort, KEYS.values.sort
    assert_equal KEYS.keys, DiagramFixtures.sources.keys
    assert_equal Diagrams::Source::TYPES.values.uniq.size, KEYS.size

    KEYS.each_key do |key|
      file = DiagramFixtures::DIR.join("#{key}.svg")
      assert file.file?, "no fixture drawing for #{key}"
      drawing = Nokogiri::XML(file.read) { |config| config.strict.nononet }
      assert_equal "svg", drawing.root.name, key
      assert_equal "http://www.w3.org/2000/svg", drawing.root.namespace&.href, key
      assert_empty drawing.xpath("//*[local-name()='foreignObject']"), "#{key} draws a foreignObject"
      assert_not_empty drawing.xpath("//*[local-name()='desc']"), "#{key} lost its accDescr"
    end
  end

  test "every sample source is of its type and passes the line rules" do
    DiagramFixtures.sources.merge(DiagramFixtures.samples).each do |key, source|
      assert Diagrams::Source.type(source), "#{key} names no type on the list"
      assert_empty Diagrams::Source.refusals(source), key
      assert_includes source, "accDescr", key
    end
  end

  # The block type's sample sources stand at the end of the same file, and
  # are no type's fixture: the task writes their drawings cleaned, into
  # db/seeds/diagrams, where the sample reads them.
  test "the block type's sample sources are split off the types' and each has its cleaned drawing" do
    assert_equal %w[sample_en sample_de sample_es], DiagramFixtures.samples.keys
    assert_equal DiagramFixtures.all_sources.keys, DiagramFixtures.sources.keys + DiagramFixtures.samples.keys
    DiagramFixtures.samples.each do |key, source|
      assert_equal "flowchart", Diagrams::Source.type(source), key
      file = DiagramFixtures::SEEDS.join("sample-#{key.delete_prefix("sample_")}.svg")
      assert file.file?, "no drawing for #{key}"
      assert_equal file.read, Diagrams::Drawing.clean(file.read).svg, "the drawing for #{key} is not stored cleaned"
    end
  end

  test "MERMAID_VERSION names the vendored file's version and SHA-256" do
    vendored = DiagramFixtures::VENDORED_VERSION.read
    file = DiagramFixtures::VENDORED

    assert_equal "12.2.0", vendored[/^version (\S+)$/, 1]
    assert_equal file.size, vendored[/^bytes (\d+)$/, 1].to_i, "mermaid.VERSION's bytes are not the vendored file's"
    assert_equal Digest::SHA256.file(file).hexdigest, vendored[/^sha256 (\h{64})$/, 1], "mermaid.VERSION's sha256 is not the vendored file's"
    assert_match(/\A"use strict";var __esbuild_esm_mermaid_nm;/, file.read(64), "the vendored file is not Mermaid's IIFE build")

    assert_equal DiagramFixtures.version_text, DiagramFixtures::VERSION_FILE.read,
      "the fixture drawings were drawn by another Mermaid: run RAILS_ENV=test bin/rails diagram:fixtures"
  end
end
