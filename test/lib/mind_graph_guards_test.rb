require "test_helper"

# Two rules of the mind graph that nothing else would catch (pages in the
# mind graph, spec §4 and decision 3). A node's publishing state is
# `Publishing::State`'s: no query and no script compares `published_at` with
# a clock or with nothing. And the graph shows the rows: no query reads a
# published copy.
class MindGraphGuardsTest < ActiveSupport::TestCase
  FILES = (Dir[Rails.root.join("app/queries/post_graph.rb")] + Dir[Rails.root.join("app/queries/post_graph/**/*.rb")] +
           Dir[Rails.root.join("app/javascript/mind_graph/**/*.js")]).freeze
  COMPARES = /published_?at\s*(?:[<>]=?|[!=]==?|\.(?:nil|present|blank|past|future|before|after)\?)|published_?at\s*\)?\s*(?:<|>)|Date\.now\(\)\s*[<>]/i
  COPIES = /Publishing\.published\b|published_all|Publishing::Listing|Publishing\.current\b/

  def code_lines
    FILES.flat_map do |path|
      File.readlines(path).each_with_index.reject { |line, _| line.match?(%r{\A\s*(#|//)}) }
          .map { |line, index| [ "#{Pathname(path).relative_path_from(Rails.root)}:#{index + 1}", line ] }
    end
  end

  test "no query and no script of the mind graph compares published_at: a node's state is Publishing::State's" do
    assert_operator FILES.size, :>, 10
    assert_empty code_lines.select { |_where, line| line.match?(COMPARES) }.map(&:first)
  end

  test "the mind graph reads the rows: no query of it reads a published copy" do
    assert_empty code_lines.select { |_where, line| line.match?(COPIES) }.map(&:first)
  end

  test "the patterns can fail" do
    [ "post.published_at.nil?", "if page.published_at > now", "node.publishedAt < Date.now()", "record.published_at == nil" ].each { |line| assert_match COMPARES, line }
    assert_no_match COMPARES, "(published_at || updated_at).to_f"
    [ "Publishing.published(page)", "Publishing.published_all(records)", "Publishing::Listing.call" ].each { |line| assert_match COPIES, line }
  end
end
