require "test_helper"

# docs/reference/theming.md prints the contract for a person, and
# Theme::Contract is what the code reads: this test keeps the two from
# drifting (theming spec, "Risks": the contract is a promise). A name added
# to the contract fails here until the reference file says it, and a name
# the file promises that the contract does not hold fails too.
#
# What it reads is the first cell of each row of a Markdown table under a
# `###` heading of `## The contract`, as its backticked name. It does not
# read what a row SAYS of its name: a wrong description is a person's to
# find.
class ThemingReferenceTest < ActiveSupport::TestCase
  DOC = Rails.root.join("docs/reference/theming.md")

  def self.section(title, text = DOC.read)
    text[/^### #{Regexp.escape(title)}\n(.*?)(?=^##|\z)/m, 1]
  end

  # The rows of the table under the heading `title`, as { name => the rest
  # of the row }.
  def self.rows(title, text = DOC.read)
    section(title, text)&.then { |found| found.scan(/^\| `([^`]+)` \|(.*)$/).to_h }
  end

  def rows(title) = self.class.rows(title) || flunk("no section \"### #{title}\" in #{DOC.basename}")

  def section(title) = self.class.section(title) || flunk("no section \"### #{title}\" in #{DOC.basename}")

  test "the tokens table names exactly the contract's tokens" do
    assert_equal Theme::Contract::TOKENS.sort, rows("Tokens").keys.sort
  end

  test "the templates table names exactly the contract's templates" do
    assert_equal Theme::Contract::TEMPLATES.keys.sort, rows("Templates").keys.sort
  end

  test "the components table names exactly the contract's components, each with the methods its template may call" do
    table = rows("Components")
    assert_equal Theme::Contract::COMPONENTS.keys.sort, table.keys.sort

    Theme::Contract::COMPONENTS.each do |path, methods|
      assert_equal methods.sort, table.fetch(path).scan(/`([a-z_?]+)`/).flatten.sort, "the methods of #{path}"
    end
  end

  test "the sentence above the components table names exactly what every component's template may call beside its own" do
    sentence = section("Components")[/every component's template may also call (.*?)\./m, 1] or flunk("no sentence \"every component's template may also call …\"")

    assert_equal Theme::Contract::COMPONENT_HELPERS.sort, sentence.scan(/`([a-z_?]+)`/).flatten.sort
  end

  # A helper's cell is its name with its arguments (`page_tree(top)`); the
  # name is what the contract holds, a question mark included.
  test "the helpers table names exactly the contract's helpers" do
    assert_equal Theme::Contract::HELPERS.sort, rows("Helpers").keys.map { |name| name[/\A[a-z_]+\??/] }.sort
  end

  test "the rich-text table names exactly the contract's selectors" do
    assert_equal Theme::Contract::RICH_TEXT.sort, rows("Rich text selectors").keys.sort
  end

  test "CLAUDE.md's reference index points here" do
    assert Rails.root.join("CLAUDE.md").read.include?("docs/reference/theming.md"), "CLAUDE.md's reference index has no line for docs/reference/theming.md"
  end

  # The comparison itself, on a text of its own: a row the contract lacks
  # and a contract entry with no row are both seen, and a table that follows
  # is not read into the one before it.
  test "the reading can fail: a missing row and a row too many are both seen, and a section ends at the next heading" do
    text = <<~MARKDOWN
      ## The contract

      ### Templates

      | Template | What it is |
      |---|---|
      | `pages/show.html.erb` | a page |
      | `pages/shwo.html.erb` | a stranger |

      ### Helpers

      | Helper | What it answers |
      |---|---|
      | `page_found?` | whether a page is shown |
      | `page_tree(top)` | the branch |

      ## After
      | `not_a_helper` | outside the section |
    MARKDOWN

    templates = self.class.rows("Templates", text).keys
    assert_equal [ "pages/shwo.html.erb" ], templates - Theme::Contract::TEMPLATES.keys, "a row the contract does not hold"
    assert_includes Theme::Contract::TEMPLATES.keys - templates, "pages/not_found.html.erb", "a contract entry with no row"
    assert_equal [ "page_found?", "page_tree(top)" ], self.class.rows("Helpers", text).keys
    assert_nil self.class.rows("Tokens", text)
  end
end
