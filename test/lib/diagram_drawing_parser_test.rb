require "test_helper"

# Only `Diagrams::Drawing` parses a drawing (Diagram block spec, §3 and §6).
# It is the sanitizer: what a public page prints of a drawing is what it
# wrote from its own parse tree, so a second reader of the stored SVG (a
# component that pulls its size out, a helper that adds a class) would be a
# second, unguarded way for an editor's markup to reach a page.
#
# The scan is a source grep over `app/` and `lib/`: a file that names
# `Nokogiri::XML` and says `svg` (in any case) anywhere is a parser of SVG.
# It cannot see a parse through another library or an XML parser reached by
# a name of its own; a review of the change is the guard there.
#
# A FILE IS EXEMPT ONLY BY ITS ENTRY IN `ALLOWED`, with the reason. An entry
# that matches no file fails, so the list cannot outlive what it excuses.
class DiagramDrawingParserTest < ActiveSupport::TestCase
  OWNER = "app/values/diagrams/drawing.rb".freeze

  ALLOWED = {
    "app/values/theme/icon_file.rb" =>
      "a theme's icon file, which the deployment trusts as it trusts the theme: a fence that refuses, never a reader of an editor's drawing"
  }.freeze

  def self.parsers
    Rails.root.glob("{app,lib}/**/*.{rb,erb,rake}").filter_map do |path|
      source = path.read
      path.relative_path_from(Rails.root).to_s if source.include?("Nokogiri::XML") && source.match?(/svg/i)
    end.sort
  end

  test "only Diagrams::Drawing parses SVG" do
    parsers = self.class.parsers
    assert_includes parsers, OWNER, "the sanitizer moved: this guard is looking for the wrong file"
    assert_equal [], parsers - [ OWNER ] - ALLOWED.keys
  end

  test "every allowed file still parses SVG" do
    assert_equal [], ALLOWED.keys - self.class.parsers
  end
end
