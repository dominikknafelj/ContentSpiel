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
    # A word is held while some entry of its language matches it
    # (`document @@ plainto_tsquery(config, word)`), which is the prune's
    # rule. So the writer leaves out what no entry could ever match: a word
    # whose `to_tsvector(config, word)` is empty in its language, a stopword
    # ("these", "which", and "don't", whose two halves are English stopwords;
    # "would" is not one), or the prune and the parity test would disagree.
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

      # The distinct candidate words of a document, lowercased as written and
      # never stemmed, since a correction is shown to a person; before the
      # stopword filter, which needs the database. None in a language that
      # `simple` cannot split into words (`Postgres::LIMITED`).
      def words_of(document)
        return [] if LIMITED.include?(document.language)

        document.fields.select { |field| FIELDS.include?(field.name) }
          .flat_map { |field| field.text.to_s.scan(WORD) }
          .map(&:downcase)
          .select { |word| LENGTH.cover?(word.length) && !word.match?(DIGITS) }
          .uniq
      end

      # The words of `documents` added to the vocabulary: one statement keeps
      # the words that are no stopword of their language, one insert writes
      # them, a word already there left as it is.
      def write(documents)
        candidates = documents.group_by(&:language).transform_values { |list| list.flat_map { |document| words_of(document) }.uniq }.reject { |_locale, words| words.empty? }
        return nil if candidates.empty?

        # sql: the stopword filter reads a set-returning function (unnest) in FROM, which no model's relation reads
        kept = Word.connection.select_rows(not_stopwords(candidates))
        Word.insert_all(kept.map { |locale, word| { locale: locale, word: word } }, unique_by: %i[locale word]) if kept.any? # version: none (the vocabulary is no part of a page)
        nil
      end

      # The words that no entry of their language holds, deleted: one probe
      # of the entries' GIN index per word, a language at a time since each
      # has its configuration. Answers the number of words deleted.
      def prune
        Word.distinct.pluck(:locale).sum do |locale|
          Word.where(locale: locale).where.not(SqlNodes.exists(holders(locale))).delete_all # version: none (the vocabulary is no part of a page)
        end
      end

      # `SELECT "words"."locale", "words"."word" FROM (SELECT 'en' AS locale,
      # "word"."word" AS word FROM unnest(CAST($1 AS text[])) "word" WHERE
      # to_tsvector(CAST('english' AS regconfig), "word"."word") <> CAST('' AS
      # tsvector) UNION ALL …) "words"`, each language's words one bind.
      def not_stopwords(candidates)
        selects = candidates.map do |locale, words|
          word = Arel::Table.new("word")[:word]
          lexemes = SqlNodes.function("to_tsvector", SqlNodes.cast(Postgres.config_for(locale), "regconfig"), word)
          Arel::SelectManager.new
            .from(Arel::Nodes::TableAlias.new(SqlNodes.function("unnest", SqlNodes.bound_text_array(words, name: "words")), "word"))
            .project(SqlNodes.quoted(locale).as("locale"), word.as("word"))
            .where(lexemes.not_eq(SqlNodes.cast("", "tsvector")))
            .ast
        end
        union = selects.reduce { |all, select| Arel::Nodes::UnionAll.new(all, select) }
        words = Arel::Table.new("words")
        Arel::SelectManager.new.from(Arel::Nodes::TableAlias.new(Arel::Nodes::Grouping.new(union), "words")).project(words[:locale], words[:word])
      end

      # The entries of `locale` that hold the outer statement's word.
      def holders(locale)
        query = SqlNodes.function("plainto_tsquery", SqlNodes.cast(Postgres.config_for(locale), "regconfig"), Word.arel_table[:word])
        Entry.where(locale: locale).where(Arel::Nodes::InfixOperation.new("@@", Entry.arel_table[:document], query))
      end

      private_class_method :not_stopwords, :holders
    end
  end
end
