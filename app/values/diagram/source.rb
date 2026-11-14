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
  # match a trimmed line's first word; its `markers` match anywhere in a line.
  # `class Name` alone is a class diagram's declaration and is not a rule: a
  # style is attached only through `:::`, `classDef` or `cssClass`.
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

    RULES = {
      directive: { first_words: [], markers: [ "%%{" ], ignore_case: true },
      front_matter: { first_words: [], markers: [ "---" ], first_line_only: true },
      colours: { first_words: %w[classDef cssClass style linkStyle], markers: [ ":::" ] },
      links: { first_words: %w[click link links href call], markers: [] },
      maths: { first_words: [], markers: [ "$$" ] }
    }.freeze

    # `line` is 0 for a refusal of the whole text (:too_long); `word` is nil there.
    Refusal = Data.define(:line, :rule, :word)

    BOM = "﻿".freeze

    # The first keyword when it is on the list, as typed ("graph", "stateDiagram-v2"), else nil.
    def self.type(text)
      keyword = keyword_line(text)&.last&.split(/\s+/, 2)&.first
      keyword if TYPES.key?(keyword)
    end

    def self.refusals(text)
      text = text.to_s
      return [ Refusal.new(line: 0, rule: :too_long, word: nil) ] if text.length > MAX_CHARACTERS

      lines = text.delete_prefix(BOM).lines.map(&:chomp)
      found = []
      index = lines.index { |line| !line.strip.empty? }
      return found unless index

      first = lines[index].strip
      if first == "---"
        found << Refusal.new(line: index + 1, rule: :front_matter, word: "---")
      else
        word = first.split(/\s+/, 2).first
        found << Refusal.new(line: index + 1, rule: :type, word: word) unless TYPES.key?(word)
      end

      lines.each_with_index do |line, i|
        next if i == index && first == "---"
        found.concat(line_refusals(line, i + 1))
      end
      found
    end

    # The first non-blank line after the keyword's, trimmed, for the block's tile.
    def self.first_line(text)
      lines = text.to_s.delete_prefix(BOM).lines
      index = lines.index { |line| !line.strip.empty? }
      return unless index

      lines[(index + 1)..].map(&:strip).find { |line| !line.empty? }
    end

    def self.rules_json
      JSON.generate(
        types: TYPES, mermaid_types: MERMAID_TYPES, max_characters: MAX_CHARACTERS,
        rules: RULES
      )
    end

    def self.keyword_line(text)
      lines = text.to_s.delete_prefix(BOM).lines
      index = lines.index { |line| !line.strip.empty? }
      [ index, lines[index].strip ] if index
    end
    private_class_method :keyword_line

    # The refusals of one line, a rule at most once.
    def self.line_refusals(line, number)
      first_word = line.strip.split(/\s+/, 2).first
      RULES.filter_map do |rule, spec|
        next if spec[:first_line_only]

        word = spec[:first_words].find { |w| w == first_word } ||
          spec[:markers].find { |m| spec[:ignore_case] ? line.downcase.include?(m.downcase) : line.include?(m) }
        Refusal.new(line: number, rule: rule, word: word) if word
      end
    end
    private_class_method :line_refusals
  end
end
