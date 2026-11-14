require "test_helper"

class Diagrams::SourceTest < ActiveSupport::TestCase
  Refusal = Diagrams::Source::Refusal

  def refusals(text) = Diagrams::Source.refusals(text)

  Diagrams::Source::TYPES.each_key do |keyword|
    test "a source whose first keyword is on the list has no refusal: #{keyword}" do
      assert_empty refusals("#{keyword} TD\n  A --> B")
      assert_equal keyword, Diagrams::Source.type("#{keyword} TD\n  A --> B")
    end
  end

  test "another Mermaid diagram's keyword is refused as :type, naming the word" do
    assert_equal [ Refusal.new(line: 1, rule: :type, word: "mindmap") ], refusals("mindmap\n  root")
    assert_nil Diagrams::Source.type("mindmap\n  root")
  end

  test "a first word that is no Mermaid diagram is refused as :no_type, naming the word" do
    assert_equal [ Refusal.new(line: 1, rule: :no_type, word: "hello") ], refusals("hello world")
  end

  test "%% comment lines are skipped before the keyword, as blank lines are" do
    assert_empty refusals("%% a note\n\n%% another\nflowchart LR")
    assert_equal "flowchart", Diagrams::Source.type("%% a note\nflowchart LR")
    assert_equal [ Refusal.new(line: 2, rule: :no_type, word: "hello") ], refusals("%% a note\nhello")
  end

  test "a %%{ first line is refused as :directive alone, never also as a type" do
    assert_equal [ Refusal.new(line: 1, rule: :directive, word: "%%{") ], refusals("%%{init: {}}%%\nflowchart LR")
  end

  test "a leading BOM and blank lines are skipped before the keyword" do
    assert_empty refusals("﻿\n\nflowchart LR")
    assert_equal "flowchart", Diagrams::Source.type("﻿\n\nflowchart LR")
  end

  test "%%{ is refused anywhere in a line, in any case" do
    assert_equal [ Refusal.new(line: 2, rule: :directive, word: "%%{") ], refusals("flowchart LR\n  A --> B %%{init: {}}%%")
    assert_equal [ :directive ], refusals("flowchart LR\n  %%{INIT: {}}%%").map(&:rule)
  end

  test "--- as the first non-blank line is :front_matter" do
    assert_equal [ Refusal.new(line: 2, rule: :front_matter, word: "---") ], refusals("\n---\ntitle: x\n---\nflowchart LR").first(1)
    assert_empty refusals("flowchart LR\n---")
  end

  test "classDef, cssClass, style, linkStyle and ::: are :colours" do
    [ "classDef a fill:#f00", "cssClass \"A\" a", "style A fill:#f00", "linkStyle 0 stroke:red", "  style A fill:#f00" ].each do |line|
      assert_equal [ :colours ], refusals("flowchart LR\n#{line}").map(&:rule), line
    end
    assert_equal [ Refusal.new(line: 2, rule: :colours, word: ":::") ], refusals("flowchart LR\n  A:::warm --> B")
    assert_equal [ Refusal.new(line: 2, rule: :colours, word: ":::") ], refusals("classDiagram\n  class Foo:::warm")
  end

  test "class Foo in a class diagram is not refused" do
    assert_empty refusals("classDiagram\n  class Animal")
  end

  test "class is :colours in a flowchart and in a state diagram" do
    assert_equal [ Refusal.new(line: 2, rule: :colours, word: "class") ], refusals("flowchart LR\n  class A warm")
    assert_equal [ Refusal.new(line: 2, rule: :colours, word: "class") ], refusals("stateDiagram-v2\n  class Idle warm")
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
    assert_operator text.length, :>, Diagrams::Source::MAX_CHARACTERS
    assert_equal [ Refusal.new(line: 0, rule: :too_long, word: nil) ], refusals(text)
    assert_equal "flowchart", Diagrams::Source.type(text)
  end

  test "an empty or blank source has no refusal" do
    assert_empty refusals("")
    assert_empty refusals("  \n\n")
    assert_empty refusals(nil)
    assert_nil Diagrams::Source.type("")
  end

  test "first_line is the first non-blank line after the keyword's" do
    assert_equal "A --> B", Diagrams::Source.first_line("flowchart LR\n\n  A --> B\n  B --> C")
    assert_nil Diagrams::Source.first_line("flowchart LR")
    assert_nil Diagrams::Source.first_line("")
  end

  # The tile shows what the drawing draws: Mermaid's accessibility lines (the
  # title, a one-line description and a description block) are the
  # description's words, and a comment is nobody's.
  test "first_line skips accTitle, accDescr, an accDescr block and comments" do
    source = "flowchart LR\n  %% a note\n  accTitle: Flow\n  accDescr: One line.\n  accDescr {\n    Two\n    lines.\n  }\n  A --> B"
    assert_equal "A --> B", Diagrams::Source.first_line(source)
    assert_equal "A --> B", Diagrams::Source.first_line("flowchart LR\n  accDescr{ on one line }\n  A --> B")
    assert_nil Diagrams::Source.first_line("flowchart LR\n  accDescr {\n    never closed\n    A --> B")
    assert_equal "A[Draft] --> B{Review}", Diagrams::Source.first_line(BlockTypes::Diagram::SAMPLE_SOURCES["en"])
  end

  test "rules_json parses to the types, the mermaid types, the limit and each rule's words and markers" do
    json = JSON.parse(Diagrams::Source.rules_json)
    assert_equal Diagrams::Source::TYPES, json["types"]
    assert_equal Diagrams::Source::MERMAID_TYPES, json["mermaid_types"]
    assert_equal Diagrams::Source::MAX_CHARACTERS, json["max_characters"]
    assert_equal %w[classDef class cssClass style linkStyle], json["rules"]["colours"]["first_words"]
    assert_equal({ "class" => [ "classDiagram" ] }, json["rules"]["colours"]["except_types"])
    assert_equal Diagrams::Source::OTHER_MERMAID_TYPES, json["other_mermaid_types"]
    assert_equal "---", json["front_matter"]
    assert_equal [ ":::" ], json["rules"]["colours"]["markers"]
    assert_equal [ "%%{" ], json["rules"]["directive"]["markers"]
    assert_equal %w[click link links href call], json["rules"]["links"]["first_words"]
    assert_equal [ "$$" ], json["rules"]["maths"]["markers"]
  end
end
