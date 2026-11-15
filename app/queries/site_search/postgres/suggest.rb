module SiteSearch
  class Postgres
    # The built-in's title suggestions (search 2 spec §4.3): the entries of
    # the query's language that a visitor sees now (`Visible`) whose title
    # has a word that begins with each word of the prefix. A title that
    # begins with the prefix comes first, then shorter titles, then type and
    # id; `limit` of them.
    #
    # The match is `to_tsvector('simple', title) @@ to_tsquery('simple', $p)`,
    # which `index_search_entries_on_title_words` serves. `simple` and not
    # the language's configuration, because a stem is no prefix: "deploym"
    # begins no word of the stem "deploy". `$p` (`tsquery_text`) is built
    # from the prefix's letters, marks and digits alone, each written
    # `'word':*` and joined by `&`, so no operator of the tsquery language
    # can be written; a prefix with none asks nothing. In a `LIMITED`
    # language, which `simple` splits on spaces it does not write, the
    # title contains the text instead (`ILIKE` with
    # `SqlNodes.like_pattern`, a scan over one language's titles).
    #
    # The prefix reaches the database only as binds named `q`, and the one
    # statement runs in a rolled-back transaction of its own under the time
    # left before the deadline, as `Query`'s do.
    class Suggest
      WORD = /[\p{L}\p{M}\p{N}]+/

      # `'albatross':* & 'gul':*` for "albatross:* & !gul|", lowercased; nil
      # when nothing but syntax was typed.
      def self.tsquery_text(text)
        words = text.to_s.downcase.scan(WORD).uniq
        words.map { |word| "'#{word}':*" }.join(" & ").presence
      end

      def initialize(query, deadline:)
        @query = query
        @timed = Query.new(query, deadline: deadline)
      end

      # `SiteSearch::Suggestion`s, best first; none, and no statement, for a
      # prefix of syntax alone.
      def items
        return [] unless limited? || self.class.tsquery_text(@query.text)

        answer = nil
        Entry.transaction(requires_new: true) do
          answer = @timed.in_time_left { rows }
          raise ActiveRecord::Rollback
        end
        answer
      end

      private

      def rows
        Entry.where(locale: @query.language).where(title_match).where(Visible.new(now: @query.now).all)
          .order(Arel::Nodes::Descending.new(Arel::Nodes::Grouping.new(begins)), SqlNodes.function("length", title).asc, entries[:record_type].asc, entries[:record_id].asc)
          .limit(@query.limit)
          .pluck(:record_type, :record_id, :published_version_id)
          .each_with_index.map do |(record_type, record_id, copy_id), index|
            Suggestion.new(record_type: record_type, record_id: record_id, copy_id: copy_id, rank: -index)
          end
      end

      def title_match
        return SqlNodes.ilike(title, SqlNodes.bound(SqlNodes.like_pattern(@query.text), name: "q")) if limited?

        simple = SqlNodes.cast("simple", "regconfig")
        Arel::Nodes::InfixOperation.new("@@", SqlNodes.function("to_tsvector", simple, title),
          SqlNodes.function("to_tsquery", simple, SqlNodes.bound(self.class.tsquery_text(@query.text), name: "q")))
      end

      # The title begins with the prefix as typed.
      def begins = SqlNodes.ilike(title, SqlNodes.bound(SqlNodes.like_pattern(@query.text, prefix: true), name: "q"))

      def limited? = LIMITED.include?(@query.language)

      def title = entries[:title]

      def entries = Entry.arel_table
    end
  end
end
