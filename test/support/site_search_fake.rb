# A search backend that keeps its documents in memory, for the tests of the
# code around a backend (indexing, the sync job, the results, System
# status). It obeys the contract (`SiteSearch::Backend`), which
# test/models/site_search/fake_test.rb holds it to with the shared
# contract test. Words are matched downcased and whole, every word of the
# query in some field of the document; a match in a heavier field ranks
# higher.
#
#   SiteSearch::Fake.new(raise_with: RuntimeError.new("…"))  # every method raises it
#   SiteSearch::Fake.new(sleep_for: 5)                        # slow; past the deadline it raises Timeout::Error at the deadline
#
# `documents` is every stored document by key, for a test to read.
class SiteSearch::Fake
  WEIGHTS = { a: 1.0, b: 0.4, c: 0.2, d: 0.1 }.freeze
  WORD = /[[:alnum:]]+/
  SNIPPET = 160

  attr_reader :documents

  def initialize(raise_with: nil, sleep_for: nil)
    @raise_with = raise_with
    @sleep_for = sleep_for
    @documents = {}
  end

  def index(documents)
    trouble!
    documents.each { |document| @documents[document.key] = document }
    nil
  end

  def remove(record_type:, record_id:, copy_ids: nil, languages: nil)
    trouble!
    @documents.delete_if do |_key, document|
      document.record_type == record_type && document.record_id == record_id &&
        (copy_ids.nil? || copy_ids.include?(document.copy_id)) && (languages.nil? || languages.include?(document.language))
    end
    nil
  end

  def prune_record(record_type:, record_id:, except_copy_ids:)
    trouble!
    @documents.delete_if do |_key, document|
      document.record_type == record_type && document.record_id == record_id && !except_copy_ids.include?(document.copy_id)
    end
    nil
  end

  def clear
    @documents.clear
    nil
  end

  def search(query, deadline:)
    trouble!(deadline)
    words = query.text.downcase.scan(WORD).uniq
    matches = @documents.values.filter_map do |document|
      next unless document.language == query.language && shown?(document, query.now)

      rank = rank_of(document, words)
      [ document, rank ] if rank
    end
    matches.sort_by! { |document, rank| [ -rank, document.key ] }
    hits = matches.drop(query.offset).first(query.per_page).map do |document, rank|
      SiteSearch::Hit.new(record_type: document.record_type, record_id: document.record_id, copy_id: document.copy_id,
        language: document.language, snippet: snippet_of(document, words), rank: rank)
    end
    SiteSearch::Results.new(hits: hits, total: matches.size)
  end

  def health(deadline:)
    trouble!(deadline)
    SiteSearch::Health.new(status: :ok, detail: nil)
  end

  private

  def shown?(document, now) = document.shown_from <= now && (document.shown_until.nil? || now < document.shown_until)

  # Nil unless every word is in some field; else the sum, per word, of the
  # heaviest field it is in.
  def rank_of(document, words)
    return nil if words.empty?

    words.sum do |word|
      weights = document.fields.select { |field| field.text.downcase.scan(WORD).include?(word) }.map { |field| WEIGHTS.fetch(field.weight) }
      return nil if weights.empty?

      weights.max
    end
  end

  # A window of the first text (the body's first) that holds a word, from
  # shortly before that word, with every whole occurrence of a word inside
  # it marked.
  def snippet_of(document, words)
    text = [ document.text, *document.fields.map(&:text) ].find { |each| (each.downcase.scan(WORD) & words).any? } || ""
    first = words.filter_map { |word| text.downcase.index(word) }.min || 0
    window = text[[ first - 40, 0 ].max, SNIPPET]
    marks = []
    window.downcase.scan(WORD) do
      match = Regexp.last_match
      marks << [ match.begin(0), match[0].length ] if words.include?(match[0])
    end
    SiteSearch::Snippet.new(text: window, marks: marks)
  end

  def trouble!(deadline = nil)
    if @sleep_for
      left = deadline ? deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC) : @sleep_for
      sleep [ @sleep_for, left ].min.clamp(0, nil)
      raise Timeout::Error, "the search backend did not answer by its deadline" if @sleep_for > left
    end
    raise @raise_with if @raise_with
  end
end
