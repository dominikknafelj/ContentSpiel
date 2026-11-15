module SiteSearch
  # The built-in search backend (search spec §6): the documents as rows of
  # `search_entries` (`SiteSearch::Entry`), one per published copy and
  # language, each a weighted tsvector built with its language's text search
  # configuration, and the query `SiteSearch::Postgres::Query`, which joins
  # the site's own tables with the clock in the query, so a scheduled copy is
  # searchable at its `live_at` with no job.
  #
  # `search_entries` is derived, like `public_paths`: written only here, in
  # the caller's transaction (its registration's `inline: true`), never by hand. Its foreign key to
  # the copy is `ON DELETE CASCADE` on purpose: a withdrawn pending copy and
  # a purged record's copies take their entries with them in the same
  # statement, and nothing ever has to refuse a copy's delete for its entries
  # (the NO ACTION rule is the library images', which must refuse).
  #
  # The view of a document (`shown_from`, `shown_until`) is not stored: the
  # query reads it from the entries' `live_at` and the records' rows at the
  # visitor's `now`, which is the same rule `Publishing.current` and the
  # resolver apply.
  class Postgres
    # Every language the CMS can serve, to the configuration Postgres 17 and
    # 18 ship for it, `simple` where Postgres has none (spec §6.2). An entry
    # is built with its language's configuration whatever language its text
    # came from (a Spanish entry holding an English title stems it as
    # Spanish), because the query is parsed with the visitor's and the two
    # must agree.
    STEMMED = {
      "ar" => "arabic", "ca" => "catalan", "da" => "danish", "de" => "german", "el" => "greek", "en" => "english",
      "es" => "spanish", "fi" => "finnish", "fr" => "french", "hi" => "hindi", "hu" => "hungarian", "id" => "indonesian",
      "it" => "italian", "lt" => "lithuanian", "nb" => "norwegian", "nl" => "dutch", "pt" => "portuguese",
      "ro" => "romanian", "ru" => "russian", "sr" => "serbian", "sv" => "swedish", "tr" => "turkish"
    }.freeze
    CONFIGS = SUPPORTED_LOCALES.keys.index_with { |code| STEMMED.fetch(code, "simple") }.freeze

    # The languages `simple` splits on spaces they do not write between
    # words (Japanese, Chinese, Thai) or between the words of a phrase
    # (Korean), so a whole run of text alone matches: they are searched by
    # the text a page contains (`Contains`), with no vocabulary, no close
    # pass and no correction. System status says so while one is switched
    # on (spec §10).
    LIMITED = %w[ja ko th zh].freeze

    # The close pass (search 2 spec §3.3, `Close`): it runs when the exact
    # pass found fewer than `CLOSE_BELOW` hits, so with 1 only when it found
    # nothing, and a page is all exact or all close; it and the contains
    # pass (`Contains`) get `CLOSE_SHARE` seconds of the deadline at most.
    # A query word of `CLOSE_WORD_LENGTH` characters or more is corrected,
    # up to `MAX_CLOSE_WORDS` of them, each to the `CANDIDATES` words of the
    # vocabulary at least `SIMILARITY` like it, `pg_trgm`'s own default:
    # measured, deploymnet/deployment is 0.47, serch/search 0.44,
    # recieve/receive 0.33, so 0.4 would lose "recieve".
    CLOSE_BELOW = 1
    CLOSE_SHARE = 1
    SIMILARITY = 0.3
    CANDIDATES = 3
    MAX_CLOSE_WORDS = 6
    CLOSE_WORD_LENGTH = 4

    # The snippet's marks as `ts_headline` writes them (spec §6.4): two
    # characters `SiteSearch::Documents` takes out of every stored text, so
    # each one in a headline is a mark.
    START_MARK = "\u{E000}".freeze
    STOP_MARK = "\u{E001}".freeze

    # Moves when what the built-in stores of a document changes for the same
    # document (a column, a rule of what it keeps beside the tsvector), so an
    # index stored by older rules is stale (`IndexState.fingerprint`), as
    # `Documents::REVISION` does for the documents themselves.
    REVISION = 1

    # `title` is the title field's plain text, which the suggestions read
    # by its `simple` words (`index_search_entries_on_title_words`).
    COLUMNS = %i[published_version_id record_type record_id locale config live_at document text created_at title].freeze

    def self.config_for(code) = CONFIGS.fetch(code.to_s, "simple")

    # A headline as a `SiteSearch::Snippet`: the marks taken out, and the
    # places of the text between each pair recorded, in characters.
    def self.snippet_of(headline)
      text = +""
      marks = []
      start = nil
      headline.to_s.each_char do |char|
        case char
        when START_MARK then start = text.length
        when STOP_MARK
          marks << [ start, text.length - start ] if start && text.length > start
          start = nil
        else text << char
        end
      end
      Snippet.new(text: text, marks: marks)
    end

    # Each document's entry replaced: the rows of its copy and language
    # deleted, the new ones inserted, and their words added to the
    # vocabulary (`Vocabulary`), in one transaction. Every writer of the
    # entries comes through here, so the vocabulary holds every word some
    # entry holds by `document @@ plainto_tsquery(config, word)` (no stopword
    # does); a word of an entry gone stays until a prune.
    def index(documents)
      return nil if documents.empty?

      Entry.transaction do
        Entry.where([ :published_version_id, :locale ] => documents.map { |document| [ document.copy_id, document.language ] }).delete_all # version: none (the search index is no part of a page: results are never cached, §8.1)
        Entry.connection.insert(insert_of(documents)) # version: none (the search index is no part of a page: results are never cached, §8.1)
        Vocabulary.write(documents)
      end
      nil
    end

    def remove(record_type:, record_id:, copy_ids: nil, languages: nil)
      entries = Entry.where(record_type: record_type, record_id: record_id)
      entries = entries.where(published_version_id: copy_ids) unless copy_ids.nil?
      entries = entries.where(locale: languages) unless languages.nil?
      entries.delete_all # version: none (the search index is no part of a page: results are never cached, §8.1)
      nil
    end

    def prune_record(record_type:, record_id:, except_copy_ids:)
      Entry.where(record_type: record_type, record_id: record_id).where.not(published_version_id: except_copy_ids).delete_all # version: none (the search index is no part of a page: results are never cached, §8.1)
      nil
    end

    def clear
      Entry.delete_all # version: none (the search index is no part of a page: results are never cached, §8.1)
      Word.delete_all # version: none (the vocabulary is no part of a page)
      nil
    end

    def search(query, deadline:) = Query.new(query, deadline: deadline).results

    # The database is the site's own: when it is down, nothing of the site
    # answers, search least of all.
    def health(deadline:) = Health.new(status: :ok, detail: nil)

    # How many records have an entry: what System status counts as indexed.
    def entry_count = Entry.from(Entry.select(:record_type, :record_id).distinct, :records).count

    private

    # `INSERT INTO search_entries (…) SELECT … UNION ALL SELECT …`, one
    # SELECT per document: Arel's VALUES list quotes every value it is
    # handed, and an entry's `document` is an expression, never a value.
    def insert_of(documents)
      table = Entry.arel_table
      now = Time.current
      rows = documents.map { |document| Arel::SelectManager.new.project(*row_of(document, now)).ast }
      Arel::InsertManager.new(table).tap do |manager|
        manager.columns.concat(COLUMNS.map { |column| table[column] })
        manager.select(rows.reduce { |all, row| Arel::Nodes::UnionAll.new(all, row) })
      end
    end

    # A literal's type is not known in a SELECT list, so the moments are cast.
    def row_of(document, now)
      config = self.class.config_for(document.language)
      [ document.copy_id, document.record_type, document.record_id, document.language, config,
        SqlNodes.cast(document.live_at, "timestamp"), vector_of(document, config), document.text, SqlNodes.cast(now, "timestamp"), title_of(document) ]
        .map { |value| SqlNodes.quoted(value) }
    end

    def title_of(document) = document.fields.find { |field| field.name == "title" }&.text.to_s

    # `setweight(to_tsvector(config, title), 'A') || setweight(…, 'B') || …`:
    # every field with the document's configuration and its own weight. A
    # document always has fields (`SiteSearch::Documents` gives every one a
    # title, even blank); one with none would make no vector, so it is refused.
    def vector_of(document, config)
      raise ArgumentError, "a search document has no fields: #{document.key}" if document.fields.empty?

      regconfig = SqlNodes.cast(config, "regconfig")
      document.fields
        .map { |field| SqlNodes.function("setweight", SqlNodes.function("to_tsvector", regconfig, field.text), field.weight.to_s.upcase) }
        .reduce { |all, weighted| Arel::Nodes::InfixOperation.new("||", all, weighted) }
    end
  end
end
