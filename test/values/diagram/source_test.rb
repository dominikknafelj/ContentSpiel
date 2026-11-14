require "test_helper"

class Diagram::SourceTest < ActiveSupport::TestCase
  Refusal = Diagram::Source::Refusal

  def refusals(text) = Diagram::Source.refusals(text)

  Diagram::Source::TYPES.each_key do |keyword|
    test "a source whose first keyword is on the list has no refusal: #{keyword}" do
      assert_empty refusals("#{keyword} TD\n  A --> B")
      assert_equal keyword, Diagram::Source.type("#{keyword} TD\n  A --> B")
    end
  end

  test "a first line not on the list is refused as :type, naming the word" do
    assert_equal [ Refusal.new(line: 1, rule: :type, word: "mindmap") ], refusals("mindmap\n  root")
    assert_nil Diagram::Source.type("mindmap\n  root")
  end

  test "a leading BOM and blank lines are skipped before the keyword" do
    assert_empty refusals("﻿\n\nflowchart LR")
    assert_equal "flowchart", Diagram::Source.type("﻿\n\nflowchart LR")
  end

  test "%%{ is refused anywhere in a line, in any case" do
    assert_equal [ Refusal.new(line: 2, rule: :directive, word: "%%{") ], refusals("flowchart LR\n  A --> B %%{init: {}}%%")
    assert_equal [ :directive ], refusals("flowchart LR\n  %%{INIT: {}}%%").map(&:rule)
  end

  test "--- as the first non-blank line is :front_matter" do
    assert_equal [ Refusal.new(line: 2, rule: :front_matter, word: "---") ], refusals("\n---\ntitle: x\n---\nflowchart LR").first(1)
    assert_equal [], refusals("flowchart LR\n---").map(&:rule) - [ :front_matter ]
  end

  test "classDef, class with a style name after :::, :::, cssClass, style and linkStyle are :colours" do
    [ "classDef a fill:#f00", "cssClass \"A\" a", "style A fill:#f00", "linkStyle 0 stroke:red", "  style A fill:#f00" ].each do |line|
      assert_equal [ :colours ], refusals("flowchart LR\n#{line}").map(&:rule), line
    end
    assert_equal [ Refusal.new(line: 2, rule: :colours, word: ":::") ], refusals("flowchart LR\n  A:::warm --> B")
    assert_equal [ Refusal.new(line: 2, rule: :colours, word: ":::") ], refusals("classDiagram\n  class Foo:::warm")
  end

  test "class Foo in a class diagram is not refused" do
    assert_empty refusals("classDiagram\n  class Animal")
  end

  test "click, link, links, href and call are :links" do
    %w[click link links href call].each do |word|
      assert_equal [ Refusal.new(line: 2, rule: :links, word: word) ], refusals("flowchart LR\n  #{word} A \"https://example.com\""), word
    end
  end

  test "$$ anywhere is :maths" do
    assert_equal [ Refusal.new(line: 2, rule: :maths, word: "$$") ], refusals("flowchart LR\n  A[\"$$x^2$$\"] --> B")
  end

  test "over MAX_CHARACTERS is one :too_long refusal at line 0, and the text is not cut" do
    text = "flowchart LR\n" + ("A --> B\n" * 2_000)
    assert_operator text.length, :>, Diagram::Source::MAX_CHARACTERS
    assert_equal [ Refusal.new(line: 0, rule: :too_long, word: nil) ], refusals(text)
    assert_equal "flowchart", Diagram::Source.type(text)
  end

  test "an empty or blank source has no refusal" do
    assert_empty refusals("")
    assert_empty refusals("  \n\n")
    assert_empty refusals(nil)
    assert_nil Diagram::Source.type("")
  end

  test "first_line is the first non-blank line after the keyword's" do
    assert_equal "A --> B", Diagram::Source.first_line("flowchart LR\n\n  A --> B\n  B --> C")
    assert_nil Diagram::Source.first_line("flowchart LR")
    assert_nil Diagram::Source.first_line("")
  end

  test "rules_json parses to the types, the mermaid types, the limit and each rule's words and markers" do
    json = JSON.parse(Diagram::Source.rules_json)
    assert_equal Diagram::Source::TYPES, json["types"]
    assert_equal Diagram::Source::MERMAID_TYPES, json["mermaid_types"]
    assert_equal Diagram::Source::MAX_CHARACTERS, json["max_characters"]
    assert_equal %w[classDef cssClass style linkStyle], json["rules"]["colours"]["first_words"]
    assert_equal [ ":::" ], json["rules"]["colours"]["markers"]
    assert_equal [ "%%{" ], json["rules"]["directive"]["markers"]
    assert_equal %w[click link links href call], json["rules"]["links"]["first_words"]
    assert_equal [ "$$" ], json["rules"]["maths"]["markers"]
  end
end
