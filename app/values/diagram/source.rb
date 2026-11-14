module Diagram
  # The rules a Diagram block's Mermaid source is held to, read line by line.
  #
  # Mermaid is drawn in the visitor's browser under the theme's colours, so a
  # source may not bring its own: no directive (`%%{init}`), no front matter,
  # no colour or style statements, no clickable links (a link is an editor's
  # choice on the page, not the diagram's), no maths. A refusal names its line
  # (1-based, counted in the text as given) and the word that caused it; the
  # source is never changed to fit.
  #
  # The rules are data (`RULES`), read here and, through `rules_json`, by the
  # editor's script and the public frame, so there is one list of words.
  # Matching is case-sensitive, as Mermaid's own keywords are, except for the
  # directive's `%%{`, which Mermaid reads in any case. A rule's `first_words`
  # match a trimmed line's first word, except in the diagram types named by its
  # `except_types`; its `markers` match anywhere in a line. `class` is a colour
  # statement (it gives a node a style class) in every type but a class
  # diagram, where `class Name` declares a class.
  #
  # Before the keyword, blank lines, a leading BOM and `%%` comment lines are
  # skipped, as Mermaid skips them. Front matter (`---` as the first line of
  # the source proper) is the one rule that is not a line's: `rules_json`
  # carries its marker as `front_matter`. A first line off the list is
  # `:type` when it names another Mermaid diagram (`OTHER_MERMAID_TYPES`, which
  # the editor may not use here) and `:no_type` when it names none.
  #
  # An empty source has no refusals: the empty state is the editor's.
  module Source
    MAX_CHARACTERS = 10_000

    # The first keyword as typed -> the label an editor reads.
    TYPES = {
      "flowchart" => "Flowchart", "graph" => "Flowchart",
      "sequenceDiagram" => "Sequence",
      "classDiagram" => "Class",
      "stateDiagram" => "State", "stateDiagram-v2" => "State",
      "erDiagram" => "Entity relationship",
      "gantt" => "Gantt",
      "pie" => "Pie"
    }.freeze

    # What Mermaid calls those diagrams (`diagramType` of its parse result).
    MERMAID_TYPES = %w[flowchart-v2 sequence classDiagram stateDiagram er gantt pie].freeze

    # Mermaid's other diagrams, which the block does not offer. The C4
    # keywords are built from their parts: written whole, `C4Component` reads
    # as a component constant to the dependency guard
    # (`test/lib/dependency_direction_test.rb`), which reads strings too.
    OTHER_MERMAID_TYPES = [
      *%w[mindmap timeline gitGraph journey quadrantChart requirementDiagram],
      *%w[Context Container Component Dynamic Deployment].map { |part| "C4#{part}" },
      *%w[sankey-beta xychart-beta block-beta packet-beta kanban architecture-beta radar-beta treemap-beta zenuml info]
    ].freeze

    FRONT_MATTER = "---".freeze
    DIRECTIVE = "%%{".freeze

    RULES = {
      directive: { first_words: [], markers: [ DIRECTIVE ], ignore_case: true },
      colours: { first_words: %w[classDef class cssClass style linkStyle], markers: [ ":::" ], except_types: { "class" => %w[classDiagram] } },
      links: { first_words: %w[click link links href call], markers: [] },
      maths: { first_words: [], markers: [ "$$" ] }
    }.freeze

    # `line` is 0 for a refusal of the whole text (:too_long); `word` is nil there.
    Refusal = Data.define(:line, :rule, :word)

    BOM = "﻿".freeze

    # The first keyword when it is on the list, as typed ("graph", "stateDiagram-v2"), else nil.
    def self.type(text)
      _, line = keyword_line(text.to_s.delete_prefix(BOM).lines)
      keyword = line&.split(/\s+/, 2)&.first
      keyword if TYPES.key?(keyword)
    end

    def self.refusals(text)
      text = text.to_s
      return [ Refusal.new(line: 0, rule: :too_long, word: nil) ] if text.length > MAX_CHARACTERS

      lines = text.delete_prefix(BOM).lines.map(&:chomp)
      index, first = keyword_line(lines)
      return [] unless index

      found = []
      word = first.split(/\s+/, 2).first
      if first == FRONT_MATTER
        found << Refusal.new(line: index + 1, rule: :front_matter, word: FRONT_MATTER)
      elsif !first.start_with?(DIRECTIVE) && !TYPES.key?(word)
        found << Refusal.new(line: index + 1, rule: OTHER_MERMAID_TYPES.include?(word) ? :type : :no_type, word: word)
      end

      type = TYPES.key?(word) ? word : nil
      lines.each_with_index do |line, i|
        next if i == index && first == FRONT_MATTER
        found.concat(line_refusals(line, i + 1, type))
      end
      found
    end

    # The first non-blank line after the keyword's, trimmed, for the block's tile.
    def self.first_line(text)
      lines = text.to_s.delete_prefix(BOM).lines
      index, = keyword_line(lines)
      return unless index

      lines[(index + 1)..].map(&:strip).find { |line| !line.empty? && !comment?(line) }
    end

    def self.rules_json
      JSON.generate(
        types: TYPES, mermaid_types: MERMAID_TYPES, other_mermaid_types: OTHER_MERMAID_TYPES,
        max_characters: MAX_CHARACTERS, front_matter: FRONT_MATTER, rules: RULES
      )
    end

    # A `%%` comment line; a `%%{` directive is not one, it is refused.
    def self.comment?(stripped) = stripped.start_with?("%%") && !stripped.start_with?(DIRECTIVE)
    private_class_method :comment?

    # [index, trimmed line] of the first line that is neither blank nor a comment.
    def self.keyword_line(lines)
      index = lines.index { |line| !line.strip.empty? && !comment?(line.strip) }
      [ index, lines[index].strip ] if index
    end
    private_class_method :keyword_line

    # The refusals of one line, a rule at most once.
    def self.line_refusals(line, number, type)
      first_word = line.strip.split(/\s+/, 2).first
      RULES.filter_map do |rule, spec|
        word = spec[:first_words].find { |w| w == first_word && !Array(spec.dig(:except_types, w)).include?(type) } ||
          spec[:markers].find { |m| spec[:ignore_case] ? line.downcase.include?(m.downcase) : line.include?(m) }
        Refusal.new(line: number, rule: rule, word: word) if word
      end
    end
    private_class_method :line_refusals
  end
end
