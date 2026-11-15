require "test_helper"

# docs/reference/hosting.md's "Database requirements" is what a host reads
# before it gives ContentSpiel a database, and the message an unmet
# requirement stops with points there by the heading
# (`SiteSearch::Postgres::Requirements::DOCS_HEADING`). So the section keeps
# that heading and lists every extension `db/schema.rb` enables: a new
# `enable_extension` fails here until the section names it.
class HostingReferenceTest < ActiveSupport::TestCase
  DOC = Rails.root.join("docs/reference/hosting.md")

  test "hosting.md's Database requirements lists every extension db/schema.rb enables" do
    section = hosting_section("Database requirements")
    enabled = Rails.root.join("db/schema.rb").read.scan(/enable_extension "(?:pg_catalog\.)?([a-z_]+)"/).flatten
    assert_equal %w[pg_trgm plpgsql], enabled.sort
    enabled.each { |name| assert_includes section, "`#{name}`" }
    %w[15 UTF8 C.UTF-8].each { |word| assert_includes section, word }
  end

  test "the requirements' message names the section by its heading" do
    assert_equal "Database requirements", SiteSearch::Postgres::Requirements::DOCS_HEADING
    assert hosting_section(SiteSearch::Postgres::Requirements::DOCS_HEADING)
  end

  private
    # The text from the `## ` heading to the next `## `.
    def hosting_section(title)
      DOC.read[/^## #{Regexp.escape(title)}\n(.*?)(?=^## |\z)/m, 1] || flunk("no section \"## #{title}\" in #{DOC.basename}")
    end
end
