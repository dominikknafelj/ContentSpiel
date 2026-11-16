# A search backend that keeps its documents in memory, for the tests of the
# code around a backend (indexing, the sync job, the results, System
# status). It obeys the contract (`SiteSearch::Backend`), which
# test/models/site_search/fake_test.rb holds it to with the shared
# contract test. Words are split, then matched downcased and whole,
# every word of the query in some field of the document; a match in a
# heavier field ranks higher.
#
# CLOSE MATCHES stand in for an outside engine's (spec §7.3): when the
# query's `close_matches` is true and no document matches exactly, a
# document whose fields hold every query word or a word one edit from it
# (a letter changed, added or dropped, or two neighbours swapped) is a
# close hit; and the answer's `correction` is the query's words with each
# that no document in view holds replaced by its first close word (in
# order), nil when none changed. Its words leave out the `code` field, as
# the built-in's vocabulary does.
#
#   SiteSearch::Fake.new(raise_with: RuntimeError.new("…"))  # every method raises it
#   SiteSearch::Fake.new(sleep_for: 5)                        # slow; past the deadline it raises Timeout::Error at the deadline
#   SiteSearch::Fake.new(suggests: false)                     # answers no `suggest`, as a backend written for 0.7.0
#   fake.answer_with(results)                                 # every search answers these
#   fake.answer_for("albatross", results)                     # a search of this text answers these, before answer_with
#
# SUGGESTIONS (`suggest`, optional in the contract): the documents in
# view whose title has a word that begins with each word of the prefix,
# a title that begins with the prefix first, then shorter titles. With
# `suggests: false` the instance has no `suggest` at all, so
# `respond_to?(:suggest)` is false.
#
# `documents` is every stored document by key, `asked` every query
# searched and `suggested` every suggest query, in order, for a test to read.
# `installed { … }` makes this fake the site's backend inside the block, as
# a gem's would be (registered as "test/fake", chosen by SEARCH_BACKEND).
class SiteSearch::Fake
  WEIGHTS = { a: 1.0, b: 0.4, c: 0.2, d: 0.1 }.freeze
  WORD = /[[:alnum:]]+/
  SNIPPET = 160

  attr_reader :documents, :asked, :suggested

  def initialize(raise_with: nil, sleep_for: nil, suggests: true)
    @raise_with = raise_with
    @sleep_for = sleep_for
    @documents = {}
    @asked = []
    @suggested = []
    singleton_class.undef_method(:suggest) unless suggests
    @answers = {}
    @answer = nil
  end

  def answer_with(results)
    @answer = results
  end

  def answer_for(text, results)
    @answers[text] = results
  end

  NAME = "test/fake".freeze

  def installed
    fake = self
    SiteSearch::Backends.register NAME, label: "Fake", backend: -> { fake }
    was = ENV["SEARCH_BACKEND"]
    ENV["SEARCH_BACKEND"] = NAME
    SiteSearch::Backends.forget!
    yield self
  ensure
    was.nil? ? ENV.delete("SEARCH_BACKEND") : ENV["SEARCH_BACKEND"] = was
    SiteSearch::Backends.forget!
    Rails.application.reloader.prepare!
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
    @asked << query
    return @answers.fetch(query.text) if @answers.key?(query.text)
    return @answer if @answer

    words = words_of(query.text).uniq
    visible = @documents.values.select { |document| document.language == query.language && shown?(document, query.now) }
    matches = ranked(visible, words) { |field_words, word| field_words.include?(word) }
    close = matches.empty? && query.close_matches
    matches = ranked(visible, words) { |field_words, word| field_words.any? { |each| one_edit?(each, word) } } if close
    hits = matches.drop(query.offset).first(query.per_page).map do |document, rank|
      SiteSearch::Hit.new(record_type: document.record_type, record_id: document.record_id, copy_id: document.copy_id,
        language: document.language, snippet: snippet_of(document, words, close: close), rank: rank, close: close)
    end
    SiteSearch::Results.new(hits: hits, total: matches.size, correction: (correction_of(visible, words) if close))
  end

  def suggest(query, deadline:)
    trouble!(deadline)
    @suggested << query
    words = words_of(query.text).uniq
    return SiteSearch::Suggestions.new(items: []) if words.empty?

    found = @documents.values.select do |document|
      title = words_of(title_text(document))
      document.language == query.language && shown?(document, query.now) && words.all? { |word| title.any? { |each| each.start_with?(word) } }
    end
    ordered = found.sort_by { |document| [ title_text(document).downcase.start_with?(query.text.downcase) ? 0 : 1, title_text(document).length, document.key ] }
    SiteSearch::Suggestions.new(items: ordered.first(query.limit).each_with_index.map do |document, index|
      SiteSearch::Suggestion.new(record_type: document.record_type, record_id: document.record_id, copy_id: document.copy_id, rank: -index)
    end)
  end

  def health(deadline:)
    trouble!(deadline)
    SiteSearch::Health.new(status: :ok, detail: nil)
  end

  private

  def title_text(document) = document.fields.find { |field| field.name == "title" }&.text.to_s

  def shown?(document, now) = document.shown_from <= now && (document.shown_until.nil? || now < document.shown_until)

  # `[document, rank]` of each document that holds every word, best first.
  def ranked(documents, words, &holds)
    matches = documents.filter_map do |document|
      rank = rank_of(document, words, &holds)
      [ document, rank ] if rank
    end
    matches.sort_by { |document, rank| [ -rank, document.key ] }
  end

  # Nil unless every word is in some field (`holds`, handed a field's words
  # and the query's word); else the sum, per word, of the heaviest field it
  # is in.
  def rank_of(document, words)
    return nil if words.empty?

    words.sum do |word|
      weights = document.fields.select { |field| yield(words_of(field.text), word) }.map { |field| WEIGHTS.fetch(field.weight) }
      return nil if weights.empty?

      weights.max
    end
  end

  # The words, each that no visible document holds outside its code
  # replaced by the first such word one edit from it; nil when no word
  # changed.
  def correction_of(documents, words)
    known = documents.flat_map { |document| document.fields.reject { |field| field.name == "code" }.flat_map { |field| words_of(field.text) } }.uniq
    corrected = words.map { |word| known.include?(word) ? word : known.find { |each| one_edit?(each, word) } || word }
    corrected.join(" ") unless corrected == words
  end

  # Whether `a` and `b` are the same word or one edit apart: a letter
  # changed, added or dropped, or two neighbours swapped.
  def one_edit?(a, b)
    return true if a == b
    return false if (a.length - b.length).abs > 1

    if a.length == b.length
      differ = (0...a.length).reject { |index| a[index] == b[index] }
      differ.size == 1 || (differ.size == 2 && differ.last == differ.first + 1 && a[differ.first] == b[differ.last] && a[differ.last] == b[differ.first])
    else
      short, long = [ a, b ].sort_by(&:length)
      (0..short.length).any? { |index| long[0, index] + long[(index + 1)..] == short }
    end
  end

  # A window of the first text (the body's first) that holds a word, from
  # shortly before that word's first whole occurrence, with every whole
  # occurrence of a word inside it marked. The words are found in the text
  # itself and compared downcased one by one, so an offset is always the
  # text's (a downcase can be longer than its word: "İ" is two characters).
  def snippet_of(document, words, close: false)
    text = [ document.text, *document.fields.map(&:text) ].find { |each| whole_words(each, words, close: close).any? } || ""
    first = whole_words(text, words, close: close).first&.first || 0
    window = text[[ first - 40, 0 ].max, SNIPPET]
    SiteSearch::Snippet.new(text: window, marks: whole_words(window, words, close: close))
  end

  # The words of `text` as matched: split first, then downcased, so a
  # letter whose downcase is longer ("İ", "i" and a combining dot) splits
  # no word. `whole_words` splits the same way.
  def words_of(text) = text.scan(WORD).map(&:downcase)

  # `[start, length]` of each whole word of `text` that is one of `words`,
  # or with `close` one edit from one of them.
  def whole_words(text, words, close: false)
    marks = []
    text.scan(WORD) do
      match = Regexp.last_match
      word = match[0].downcase
      marks << [ match.begin(0), match[0].length ] if close ? words.any? { |each| one_edit?(word, each) } : words.include?(word)
    end
    marks
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
