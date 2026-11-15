module SiteSearch
  class Postgres
    # The site's words per language (`search_words`, `SiteSearch::Word`),
    # from which close matches and the correction draw their candidates
    # (search 2 spec §3.2). Written by `Postgres#index` alone, after the
    # entries and in the same transaction, so every writer of the entries
    # (a copy taken, a slug's re-index, a rewrite, a build) writes the words
    # of what it indexed. Pruned at the end of every build (`Rebuild`) and by
    # `SiteSearch::PruneWordsJob` after a purge or a withdrawn copy.
    #
    # ONE RULE FOR THE VOCABULARY: a word is in it while some entry of its
    # language holds it, `document @@ plainto_tsquery(config, word)`. The
    # writer keeps a candidate only where an entry it has just written holds
    # it by that test, and the prune deletes a word no entry holds by it, so
    # the two never disagree. A stopword ("these", "which", "don't", whose
    # two halves are English stopwords; "would" is not one) makes an empty
    # tsquery, which matches nothing, and drops out by itself; so does a part
    # of a host name or an e-mail address (`example` of `example.com`), which
    # Postgres keeps as one lexeme.
    #
    # A superseded copy's entries, and so its words, stay until the record's
    # next copy or the next prune; a candidate is never shown unless a search
    # verifies it against what is shown (§3.5).
    #
    # A PRUNE AND A PUBLISH IN FLIGHT: an entry not yet committed is not seen
    # by the prune's NOT EXISTS, so the prune could delete a word that entry
    # holds after the writer found it already there. The writer takes the
    # transaction advisory lock `LOCK` shared and the prune takes it
    # exclusive, so a prune waits for the writes in flight and a write waits
    # for the prune. No guard races two connections; the test holds the
    # lock modes (`test/models/site_search/postgres/vocabulary_test.rb`).
    module Vocabulary
      module_function

      # A run of letters, marks and digits, an apostrophe allowed between two
      # of them (`don't`, `l'été`).
      WORD = /[\p{L}\p{M}\p{N}]+(?:'[\p{L}\p{M}\p{N}]+)*/
      # Under 4 characters a trigram cannot tell a typo from another word
      # (`similarity('teh', 'the')` is 0.14).
      LENGTH = 4..32
      DIGITS = /\A\p{N}+\z/
      # Never `code`: a listing's identifiers would be poor corrections.
      FIELDS = %w[title tags summary body].freeze

      # The two keys of the vocabulary's transaction advisory lock: a
      # namespace of its own beside `Rebuild::ADVISORY_NAMESPACE`, since
      # session and transaction advisory locks share one key space.
      LOCK = [ 0x5EA2C5, 1 ].freeze
      # How long a prune waits for the writes in flight before it gives up
      # (`ActiveRecord::LockWaitTimeout`, which `PruneWordsJob` retries): a
      # prune queued behind a long writer would otherwise stand in
      # Postgres's lock queue before every new publish's shared lock.
      LOCK_TIMEOUT = "2s".freeze

      # The distinct candidate words of a document, lowercased as written and
      # never stemmed, since a correction is shown to a person; before the
      # database's test of them. None in a language that `simple` cannot
      # split into words (`Postgres::LIMITED`).
      def words_of(document)
        return [] if LIMITED.include?(document.language)

        document.fields.select { |field| FIELDS.include?(field.name) }
          .flat_map { |field| field.text.to_s.scan(WORD) }
          .map(&:downcase)
          .select { |word| LENGTH.cover?(word.length) && !word.match?(DIGITS) }
          .uniq
      end

      # The words of `documents`, whose entries were just written in this
      # transaction, added to the vocabulary: one statement keeps the
      # candidates those entries hold, one insert writes them, a word already
      # there left as it is.
      def write(documents)
        candidates = documents.group_by(&:language).filter_map do |locale, list|
          words = list.flat_map { |document| words_of(document) }.uniq
          [ locale, words, list.map(&:copy_id).uniq ] if words.any?
        end
        return nil if candidates.empty?

        take_lock("pg_advisory_xact_lock_shared")
        # sql: the filter reads a set-returning function (unnest) in FROM, which no model's relation reads
        kept = Word.connection.select_rows(held_by_batch(candidates))
        Word.insert_all(kept.map { |locale, word| { locale: locale, word: word } }, unique_by: %i[locale word]) if kept.any? # version: none (the vocabulary is no part of a page)
        nil
      end

      # The words that no entry of their language holds, deleted under the
      # exclusive lock, waited for `LOCK_TIMEOUT` at most: one probe of the entries' GIN index per word, a
      # language at a time since each has its configuration. Answers the
      # number of words deleted.
      def prune
        Word.transaction do
          # sql: Arel has no node for SET; the value is a constant
          Word.connection.execute("SET LOCAL lock_timeout = '#{LOCK_TIMEOUT}'") # version: none (a setting of the prune's own transaction)
          take_lock("pg_advisory_xact_lock")
          Word.distinct.pluck(:locale).sum do |locale|
            Word.where(locale: locale).where.not(SqlNodes.exists(holders(locale, Word.arel_table[:word]))).delete_all # version: none (the vocabulary is no part of a page)
          end
        end
      end

      # Held until the transaction ends.
      def take_lock(function)
        # The lock functions return void, a type Active Record's type map does
        # not know, so the value is cast to text and no void column reaches it.
        # sql: an advisory lock is a function no relation reads; the statement is Arel
        Word.connection.select_value(Arel::SelectManager.new.project(SqlNodes.cast(SqlNodes.function(function, *LOCK), "text")))
      end

      # `SELECT "words"."locale", "words"."word" FROM (SELECT 'en' AS locale,
      # "word"."word" AS word FROM unnest(CAST($1 AS text[])) "word" WHERE
      # EXISTS (SELECT … FROM search_entries WHERE locale = 'en' AND
      # published_version_id IN (…) AND document @@ plainto_tsquery(…,
      # "word"."word")) UNION ALL …) "words"`, each language's words one bind.
      def held_by_batch(candidates)
        selects = candidates.map do |locale, words, copy_ids|
          word = Arel::Table.new("word")[:word]
          Arel::SelectManager.new
            .from(Arel::Nodes::TableAlias.new(SqlNodes.function("unnest", SqlNodes.bound_text_array(words, name: "words")), "word"))
            .project(SqlNodes.quoted(locale).as("locale"), word.as("word"))
            .where(SqlNodes.exists(holders(locale, word).where(published_version_id: copy_ids)))
            .ast
        end
        union = selects.reduce { |all, select| Arel::Nodes::UnionAll.new(all, select) }
        words = Arel::Table.new("words")
        Arel::SelectManager.new.from(Arel::Nodes::TableAlias.new(Arel::Nodes::Grouping.new(union), "words")).project(words[:locale], words[:word])
      end

      # The entries of `locale` that hold `word`, a column of the outer
      # statement, by the vocabulary's one rule.
      def holders(locale, word)
        query = SqlNodes.function("plainto_tsquery", SqlNodes.cast(Postgres.config_for(locale), "regconfig"), word)
        Entry.where(locale: locale).where(Arel::Nodes::InfixOperation.new("@@", Entry.arel_table[:document], query))
      end

      private_class_method :take_lock, :held_by_batch, :holders
    end
  end
end
