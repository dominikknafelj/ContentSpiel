require "test_helper"
require_relative "../support/source_code"

# Two sets of post types: the declared (`ContentTypes.all`, `.names`), which is
# the code's, and the switched-on (`ContentTypes.switched_on`), which is the
# site's. A reader of the declared set decides something that does not depend
# on a site's switch (who may be granted what, which names are valid); the
# public site, search and the editors' choices read the switched-on set. A
# file that reads the declared set is named here with its reason, so a new
# reader is a decision and not an accident.
class ContentTypeSetsTest < ActiveSupport::TestCase
  ROOTS = %w[app lib config db/seeds db/seeds.rb].freeze
  DECLARED = /ContentTypes\.(?:all|names)\b/

  DECLARED_READERS = {
    "app/models/access_control/permissions.rb" => "a grant scoped to a switched-off type stays live: it decides who may read, trash and purge its posts",
    "app/components/admin/mind_graph_screen/legend_component.rb" => "retired means undeclared",
    "app/controllers/admin/posts_controller.rb" => "the posts list's type filter reads the declared set until it takes the types present from `Posts::List#types_present`",
    "app/services/settings/save.rb" => "the switch is normalised against the declared names",
    "db/seeds.rb" => "development switches every declared type on",
    "app/models/site_setting.rb" => "the at-least-one rule counts declared names"
  }.freeze

  def self.files
    ROOTS.flat_map { |root| File.directory?(Rails.root.join(root)) ? Dir[Rails.root.join(root, "**", "*.{rb,erb}")] : Dir[Rails.root.join(root)] }
      .map { |path| Pathname(path).relative_path_from(Rails.root).to_s }.sort
  end

  def readers
    self.class.files.filter_map do |path|
      lines = SourceCode.code_of(Rails.root.join(path).to_s).lines
      hits = lines.each_index.select { |index| lines[index].match?(DECLARED) }
      [ path, hits.map { |index| index + 1 } ] if hits.any?
    end.to_h
  end

  test "every reader of the declared post types is named, with its reason" do
    unnamed = readers.reject { |path, _lines| DECLARED_READERS.key?(path) }

    assert_empty unnamed, "these read the declared post types (ContentTypes.all / .names) and are not in DECLARED_READERS; " \
      "read ContentTypes.switched_on (names) instead, or name the file with its reason:\n" \
      "#{unnamed.map { |path, lines| "#{path}:#{lines.join(',')}" }.join("\n")}"
  end

  test "no entry of the declared readers is stale" do
    stale = DECLARED_READERS.keys - readers.keys

    assert_empty stale, "these files no longer read the declared post types; remove their entries: #{stale.join(', ')}"
  end
end
