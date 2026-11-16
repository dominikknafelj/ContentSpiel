module SiteSearch
  class Postgres
    # The built-in's contains pass (search 2 spec §3.4), the real search in
    # the `LIMITED` languages, where `simple` finds a page only by a whole
    # run of text: an entry a visitor sees now (`Visible`) whose title or
    # body holds every whitespace-separated part of the query, by `ILIKE`
    # with `SqlNodes.like_pattern`, so a typed `%`, `_` or `\` is only
    # itself, each pattern a bind named `q`. No trigram index: a query of one
    # or two characters, the common word in these scripts, has no trigram,
    # and the language's entries are scanned, held to `CLOSE_SHARE`.
    #
    # Its hits follow the exact pass's in one list: `exclude` is the exact
    # pass's condition, whose entries are never found again, and `after` the
    # exact pass's total, where this list begins, so a page takes the rest
    # of its rows from here and a later page skips what earlier pages
    # showed. A hit holds the characters as typed, so it is never close.
    # A title that holds the first part comes first, then the earliest
    # place of it in the body.
    #
    # The query's operators are read as the exact pass reads them, never as
    # text: a `"` is taken out, a part beginning with `-` leaves out what
    # holds the rest of it, a standalone `or` is no part (so every other part
    # is still held); a query of operators alone finds nothing.
    #
    # The snippet is cut by the database (`ts_headline` cannot mark a part
    # of a word under `simple`, and a hit's text is up to `SiteSearch::MAX_TEXT`
    # characters, too long to read and scan for every hit):
    # `SNIPPET_BEFORE` characters before the first occurrence of a part and
    # `SNIPPET_LENGTH` in all, and only that cut is read and has every
    # occurrence of every part marked.
    class Contains
      SNIPPET_BEFORE = 80
      SNIPPET_LENGTH = 300

      def initialize(query, deadline:, exclude:, after: 0)
        @query = query
        @exclude = exclude
        @after = after
        @timed = Query.new(query, deadline: Query.share_of(deadline))
      end

      # In a savepoint of its own, rolled back after, so the statement
      # timeouts end with it.
      def results
        return Results.new(hits: [], total: 0) if parts.empty?

        answer = nil
        Entry.transaction(requires_new: true) do
          answer = Results.new(hits: hits, total: @timed.in_time_left { matches.count })
          raise ActiveRecord::Rollback
        end
        answer
      end

      private

      def tokens = @tokens ||= @query.text.delete('"').split.reject { |token| token.casecmp?("or") }.uniq

      def parts = @parts ||= tokens.reject { |token| token.start_with?("-") }

      def left_out = @left_out ||= tokens.filter_map { |token| token.delete_prefix("-").presence if token.start_with?("-") }.uniq

      def entries = Entry.arel_table

      def pattern(part) = SqlNodes.bound(SqlNodes.like_pattern(part), name: "q")

      def holds(column, part) = SqlNodes.ilike(entries[column], pattern(part))

      def matches
        held = parts.map { |part| holds(:title, part).or(holds(:text, part)) }.reduce(:and)
        found = Entry.where(locale: @query.language).where(held).where(Visible.new(now: @query.now).all)
        found = left_out.reduce(found) { |all, part| all.where(Arel::Nodes::Grouping.new(holds(:title, part).or(holds(:text, part))).not) }
        @exclude ? found.where(Arel::Nodes::Grouping.new(@exclude).not) : found
      end

      # This list's part of the query's page: from the page's first row or
      # this list's, whichever is later, to the page's end. A hit's rank is
      # its place in the list negated, below every exact hit's, which
      # `ts_rank_cd` never makes negative.
      def hits
        start = [ @query.offset, @after ].max
        limit = @query.offset + @query.per_page - start
        return [] unless limit.positive?

        first = parts.first
        @timed.in_time_left do
          matches
            .order(Arel::Nodes::Descending.new(Arel::Nodes::Grouping.new(holds(:title, first))), place_of(first).asc, entries[:record_type].asc, entries[:record_id].asc)
            .limit(limit).offset(start - @after)
            .pluck(:record_type, :record_id, :published_version_id, cut)
            .each_with_index.map do |(record_type, record_id, copy_id, text), index|
              Hit.new(record_type: record_type, record_id: record_id, copy_id: copy_id, language: @query.language,
                snippet: snippet_of(text), rank: -(start + index), close: false)
            end
        end
      end

      # Where `part` first stands in the text, from 1, case aside; 0 when
      # it does not.
      def place_of(part) = SqlNodes.function("strpos", SqlNodes.function("lower", entries[:text]), SqlNodes.function("lower", SqlNodes.bound(part, name: "q")))

      # The text's `SNIPPET_LENGTH` characters from `SNIPPET_BEFORE` before
      # the first place of any part (`LEAST` passes over a NULL), or from
      # its start when the text holds none.
      def cut
        first = SqlNodes.coalesce(SqlNodes.function("LEAST", *parts.map { |part| SqlNodes.function("NULLIF", place_of(part), 0) }), 1)
        start = SqlNodes.function("GREATEST", Arel::Nodes::Subtraction.new(first, SqlNodes.quoted(SNIPPET_BEFORE)), 1)
        SqlNodes.function("substr", entries[:text], start, SNIPPET_LENGTH)
      end

      def snippet_of(cut)
        cut = cut.to_s
        finders = parts.map { |part| /#{Regexp.escape(part)}/i }
        marks = finders.flat_map do |finder|
          cut.enum_for(:scan, finder).map { [ Regexp.last_match.begin(0), Regexp.last_match[0].length ] }
        end
        Snippet.new(text: cut, marks: marks.sort.each_with_object([]) { |mark, kept| kept << mark if kept.empty? || mark[0] >= kept.last.sum })
      end
    end
  end
end
