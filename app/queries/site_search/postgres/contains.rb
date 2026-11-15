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
    # The snippet is cut here (`ts_headline` cannot mark a part of a word
    # under `simple`): `SNIPPET_BEFORE` characters before the first
    # occurrence of a part and `SNIPPET_LENGTH` in all, every occurrence of
    # every part marked.
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
        answer = nil
        Entry.transaction(requires_new: true) do
          answer = Results.new(hits: hits, total: @timed.in_time_left { matches.count })
          raise ActiveRecord::Rollback
        end
        answer
      end

      private

      def parts = @parts ||= @query.text.split.uniq

      def entries = Entry.arel_table

      def pattern(part) = SqlNodes.bound(SqlNodes.like_pattern(part), name: "q")

      def holds(column, part) = SqlNodes.ilike(entries[column], pattern(part))

      def matches
        held = parts.map { |part| holds(:title, part).or(holds(:text, part)) }.reduce(:and)
        found = Entry.where(locale: @query.language).where(held).where(Visible.new(now: @query.now).all)
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
        place = SqlNodes.function("strpos", SqlNodes.function("lower", entries[:text]), SqlNodes.function("lower", SqlNodes.bound(first, name: "q")))
        @timed.in_time_left do
          matches
            .order(Arel::Nodes::Descending.new(Arel::Nodes::Grouping.new(holds(:title, first))), place.asc, entries[:record_type].asc, entries[:record_id].asc)
            .limit(limit).offset(start - @after)
            .pluck(:record_type, :record_id, :published_version_id, :text)
            .each_with_index.map do |(record_type, record_id, copy_id, text), index|
              Hit.new(record_type: record_type, record_id: record_id, copy_id: copy_id, language: @query.language,
                snippet: snippet_of(text), rank: -(start + index), close: false)
            end
        end
      end

      def snippet_of(text)
        finders = parts.map { |part| /#{Regexp.escape(part)}/i }
        first = finders.filter_map { |finder| text.index(finder) }.min
        cut = text[first ? [ first - SNIPPET_BEFORE, 0 ].max : 0, SNIPPET_LENGTH].to_s
        marks = finders.flat_map do |finder|
          cut.enum_for(:scan, finder).map { [ Regexp.last_match.begin(0), Regexp.last_match[0].length ] }
        end
        Snippet.new(text: cut, marks: marks.sort.each_with_object([]) { |mark, kept| kept << mark if kept.empty? || mark[0] >= kept.last.sum })
      end
    end
  end
end
