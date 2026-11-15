module SiteSearch
  class Postgres
    # The built-in's close pass (search 2 spec §3.3): a plain query that the
    # exact pass answered with nothing, searched again with each misspelled
    # word widened to the words of the site most like it.
    #
    # A query word is corrected when it is at least `CLOSE_WORD_LENGTH`
    # characters, not digits alone, no stopword of the language (its
    # `plainto_tsquery` is empty) and held by no entry a visitor sees now
    # (`Visible`; the vocabulary, `SiteSearch::Word`, holds hidden copies'
    # words too); the first `MAX_CLOSE_WORDS` of those get the
    # `CANDIDATES` words of the vocabulary at least `SIMILARITY` like it
    # (`pg_trgm`'s `%`, through the words' trigram index), most similar
    # first, then the smallest difference in length, then alphabetically,
    # each one HELD BY AN ENTRY A VISITOR SEES NOW (`Visible`), so a word
    # only a scheduled, pending or hidden copy holds is never offered nor
    # searched. ContentSpiel still verifies the correction for any backend
    # (`SiteSearch.verified`); this keeps the candidates from wasting it.
    #
    # The close tsquery is `(plainto_tsquery(c, $word) || plainto_tsquery(c,
    # $candidate) || …) && …` over every query word, ranked, paged and
    # marked as the exact pass's, every hit `close: true`. `plainto_tsquery`
    # reads plain text, so no word or candidate is syntax, and each is a
    # bind named `q`, never statement text. The correction is the query with
    # each corrected word replaced by its first candidate, or nil when none
    # changed.
    #
    # Everything runs in a savepoint of its own (`in_share`), rolled back
    # after, with `pg_trgm.similarity_threshold` set for it and every
    # statement held to the time left of `CLOSE_SHARE`
    # (`Query.share_of`), so a pass out of time raises
    # `ActiveRecord::QueryCanceled` and leaves the caller's transaction as
    # it was.
    class Close
      def initialize(query, deadline:)
        @query = query
        @timed = Query.new(query, deadline: Query.share_of(deadline))
        @in_share = false
      end

      # The query holds none of the operators `websearch_to_tsquery` reads:
      # a `"`, a word beginning with `-` or a standalone `or`. Correcting
      # the words of an exclusion would invert it.
      def plain?
        return false if @query.text.include?('"')

        @query.text.split.none? { |part| part.start_with?("-") || part.casecmp?("or") }
      end

      # Each corrected word, lowercased, to its candidates, best first; a
      # word with none is not a key.
      def candidates
        @candidates ||= begin
          asked = words.select { |word| word.length >= CLOSE_WORD_LENGTH && !word.match?(Vocabulary::DIGITS) }
          if asked.empty?
            {}
          else
            in_share { to_correct(asked).first(MAX_CLOSE_WORDS).to_h { |word| [ word, candidates_of(word) ] }.reject { |_, found| found.empty? } }
          end
        end
      end

      # Grouped whole, since `@@` and `&&` share a precedence and
      # `document @@ a && b` would read `(document @@ a) && b`.
      def tsquery
        Arel::Nodes::Grouping.new(words.map do |word|
          variants = [ word, *candidates.fetch(word, []) ].map { |variant| SqlNodes.function("plainto_tsquery", @timed.regconfig, SqlNodes.bound(variant, name: "q")) }
          Arel::Nodes::Grouping.new(variants.reduce { |any, variant| Arel::Nodes::InfixOperation.new("||", any, variant) })
        end.reduce { |all, word| Arel::Nodes::InfixOperation.new("&&", all, word) })
      end

      def correction
        return nil if candidates.empty?

        @query.text.gsub(Vocabulary::WORD) { |word| candidates[word.downcase]&.first || word }
      end

      # No statement but the candidates' when no word has one: the close
      # tsquery would then be the query's own words, which found nothing.
      def results
        in_share do
          next Results.new(hits: [], total: 0) if candidates.empty?

          query = tsquery
          Results.new(hits: @timed.hits_for(query, close: true), total: @timed.total_for(query), correction: correction)
        end
      end

      private

      # The query's words as the vocabulary cuts them, lowercased, once each.
      def words = @words ||= @query.text.scan(Vocabulary::WORD).map(&:downcase).uniq

      def in_share
        return yield if @in_share

        answer = nil
        Entry.transaction(requires_new: true) do
          @in_share = true
          # sql: Arel has no node for SET; the value is a constant
          Entry.connection.execute("SET LOCAL pg_trgm.similarity_threshold = #{SIMILARITY}") # version: none (a setting of the close pass's own savepoint, which writes nothing)
          answer = yield
          raise ActiveRecord::Rollback
        ensure
          @in_share = false
        end
        answer
      end

      # `asked` less the stopwords and the words an entry a visitor sees now
      # holds, in their order: one statement over `unnest($q)`. KNOWN IS
      # JUDGED BY A VISIBLE ENTRY (`held_now`), never by the vocabulary,
      # which holds the words of every indexed copy (a scheduled change, a
      # trashed record until its purge, a superseded copy until the next
      # prune): a word only such a copy holds would otherwise go uncorrected,
      # and whether a search is corrected would say whether a hidden copy
      # holds the word.
      def to_correct(asked)
        word = Arel::Table.new("word")[:word]
        statement = Arel::SelectManager.new
          .from(Arel::Nodes::TableAlias.new(SqlNodes.function("unnest", SqlNodes.bound_text_array(asked, name: "q")), "word"))
          .project(word)
          .where(SqlNodes.function("numnode", SqlNodes.function("plainto_tsquery", @timed.regconfig, word)).gt(0))
          .where(SqlNodes.exists(held_now(word)).not)
        # sql: the filter reads a set-returning function (unnest) in FROM, which no model's relation reads
        kept = @timed.in_time_left { Word.connection.select_values(statement) }
        asked & kept
      end

      def candidates_of(asked)
        words = Word.arel_table
        typed = SqlNodes.bound(asked, name: "q")
        similarity = SqlNodes.function("similarity", words[:word], typed)
        length_gap = SqlNodes.function("abs", Arel::Nodes::Subtraction.new(SqlNodes.function("length", words[:word]), SqlNodes.quoted(asked.length)))
        @timed.in_time_left do
          Word.where(locale: @query.language)
            .where(Arel::Nodes::InfixOperation.new("%", words[:word], typed))
            .where(SqlNodes.exists(held_now(words[:word])))
            .order(similarity.desc, length_gap.asc, words[:word].asc)
            .limit(CANDIDATES).pluck(:word)
        end
      end

      # The entries of the language a visitor sees now that hold `word`, a
      # column of the outer statement, by the vocabulary's one rule.
      def held_now(word)
        Entry.where(locale: @query.language)
          .where(@timed.held_by(SqlNodes.function("plainto_tsquery", @timed.regconfig, word)))
          .where(Visible.new(now: @query.now).all)
      end
    end
  end
end
