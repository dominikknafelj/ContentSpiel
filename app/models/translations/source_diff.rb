module Translations
  # A word diff between the text a translation was made from
  # (`Translations::Source#text`) and the original as it reads now, for the
  # translations screen. Pure and database-free.
  #
  #   Translations::SourceDiff.call(from: "a spare room", to: "a small room").segments
  #   # => [[:equal, "a "], [:delete, "spare"], [:insert, "small"], [:equal, " room"]]
  #
  # `from`/`to` are a String (plain field) or an Array of paragraph Strings
  # (rich text, `RichText::Document#plain_paragraphs`); nil on either side
  # means there is nothing to compare (no stored text: an old entry), and
  # yields no segments and no change.
  #
  # Cost. Words and the whitespace between them are separate tokens, and a
  # longest-common-subsequence table is (tokens x tokens) cells. One call has
  # ONE budget for the whole thing, so no input can make it expensive:
  #   * MAX_CELLS (4 million) table cells in total, paragraph-level and
  #     word-level tables combined -- every table is charged before it is
  #     built; once the budget is spent the result is `too_long?` with no
  #     segments;
  #   * MAX_WORDS (4000) per compared text, checked before anything is built;
  #   * a common prefix and suffix is trimmed first, at paragraph level and
  #     again at word level, so the usual case -- a small edit in a long
  #     text -- costs almost nothing and 20,000 one-word paragraphs with one
  #     changed cost a 1x1 table.
  # Arrays are matched paragraph-by-paragraph first (an inserted paragraph
  # must not shift every later one), so a 20,000-word body only word-diffs
  # the few paragraphs that actually changed.
  class SourceDiff
    MAX_WORDS = 4000
    MAX_CELLS = 4_000_000

    Result = Data.define(:segments, :compared, :too_long) do
      def changed? = segments.any? { |kind, _| kind != :equal }
      def too_long? = too_long

      # The texts are the same although the digests differ (the caller
      # knows they do): only formatting or markup changed.
      def formatting_only? = compared && !too_long && !changed?
    end

    def self.call(from:, to:) = new(from, to).call

    def initialize(from, to)
      @from = from
      @to = to
      @too_long = false
      @cells = 0
    end

    def call
      return result([], compared: false) if @from.nil? || @to.nil?

      segments = @from.is_a?(Array) || @to.is_a?(Array) ? paragraph_segments(Array(@from), Array(@to)) : word_segments(@from.to_s, @to.to_s)
      result(@too_long ? [] : segments, compared: true)
    end

    private

    def result(segments, compared:) = Result.new(segments, compared, @too_long)

    def paragraph_segments(from, to)
      prefix = common_prefix(from, to)
      suffix = common_suffix(from, to, prefix)
      from_middle = from[prefix...(from.size - suffix)]
      to_middle = to[prefix...(to.size - suffix)]

      segments = []
      add = ->(parts) { segments << [ :equal, "\n" ] if segments.any?; segments.concat(parts) }
      from[0, prefix].each { |paragraph| add.([ [ :equal, paragraph ] ]) }

      anchors = lcs_pairs(from_middle, to_middle)
      return [] if @too_long

      from_at = to_at = 0
      (anchors + [ [ from_middle.size, to_middle.size ] ]).each do |from_anchor, to_anchor|
        gap_from = from_middle[from_at...from_anchor]
        gap_to = to_middle[to_at...to_anchor]
        [ gap_from.size, gap_to.size ].max.times do |index|
          old_paragraph = gap_from[index]
          new_paragraph = gap_to[index]
          if old_paragraph && new_paragraph
            add.(word_segments(old_paragraph, new_paragraph))
            return [] if @too_long
          elsif old_paragraph
            add.([ [ :delete, old_paragraph ] ])
          else
            add.([ [ :insert, new_paragraph ] ])
          end
        end
        add.([ [ :equal, from_middle[from_anchor] ] ]) if from_anchor < from_middle.size
        from_at = from_anchor + 1
        to_at = to_anchor + 1
      end
      from[from.size - suffix, suffix].each { |paragraph| add.([ [ :equal, paragraph ] ]) }
      segments
    end

    def word_segments(from, to)
      if [ from, to ].any? { |text| text.scan(/\S+/).size > MAX_WORDS }
        @too_long = true
        return []
      end

      old_tokens = from.scan(/\s+|\S+/)
      new_tokens = to.scan(/\s+|\S+/)
      prefix = common_prefix(old_tokens, new_tokens)
      suffix = common_suffix(old_tokens, new_tokens, prefix)
      old_middle = old_tokens[prefix...(old_tokens.size - suffix)]
      new_middle = new_tokens[prefix...(new_tokens.size - suffix)]
      segments = []
      segments << [ :equal, old_tokens[0, prefix].join ] if prefix > 0
      segments.concat(diff_middle(old_middle, new_middle))
      return [] if @too_long

      segments << [ :equal, old_tokens[old_tokens.size - suffix, suffix].join ] if suffix > 0
      merge(segments)
    end

    def common_prefix(a, b)
      limit = [ a.size, b.size ].min
      index = 0
      index += 1 while index < limit && a[index] == b[index]
      index
    end

    def common_suffix(a, b, prefix)
      limit = [ a.size, b.size ].min - prefix
      count = 0
      count += 1 while count < limit && a[a.size - 1 - count] == b[b.size - 1 - count]
      count
    end

    # Deletes before inserts within one changed run.
    def diff_middle(old_tokens, new_tokens)
      return [] if old_tokens.empty? && new_tokens.empty?
      return [ [ :insert, new_tokens.join ] ] if old_tokens.empty?
      return [ [ :delete, old_tokens.join ] ] if new_tokens.empty?

      segments = []
      from_at = to_at = 0
      (lcs_pairs(old_tokens, new_tokens) + [ [ old_tokens.size, new_tokens.size ] ]).each do |from_anchor, to_anchor|
        segments << [ :delete, old_tokens[from_at...from_anchor].join ] if from_anchor > from_at
        segments << [ :insert, new_tokens[to_at...to_anchor].join ] if to_anchor > to_at
        segments << [ :equal, old_tokens[from_anchor] ] if from_anchor < old_tokens.size
        from_at = from_anchor + 1
        to_at = to_anchor + 1
      end
      segments
    end

    # Index pairs [i, j] of one longest common subsequence, in order.
    def lcs_pairs(a, b)
      return [] if a.empty? || b.empty?

      @cells += a.size * b.size
      @too_long = true if @cells > MAX_CELLS
      return [] if @too_long

      rows = Array.new(a.size + 1) { Array.new(b.size + 1, 0) }
      (a.size - 1).downto(0) do |i|
        row = rows[i]
        below = rows[i + 1]
        (b.size - 1).downto(0) do |j|
          row[j] = a[i] == b[j] ? below[j + 1] + 1 : [ below[j], row[j + 1] ].max
        end
      end

      pairs = []
      i = j = 0
      while i < a.size && j < b.size
        if a[i] == b[j]
          pairs << [ i, j ]
          i += 1
          j += 1
        elsif rows[i + 1][j] >= rows[i][j + 1]
          i += 1
        else
          j += 1
        end
      end
      pairs
    end

    # Adjacent runs of one kind become one segment. Done per word diff, never
    # across paragraphs, so a paragraph break stays its own [:equal, "\n"].
    def merge(segments)
      segments.each_with_object([]) do |(kind, text), merged|
        next if text.empty?

        if merged.last&.first == kind
          merged.last[1] = merged.last[1] + text
        else
          merged << [ kind, text ]
        end
      end
    end
  end
end
