# The tests every search backend passes (spec §5.1), the contract
# `SiteSearch::Backend`'s comment states. A backend's own test includes this
# module and defines two methods:
#
#   def backend = @backend ||= Acme::SolrBackend.new(url: …)
#   def contract_document(title:, body: "", code: "", language: "en", shown_from: nil, shown_until: nil) = …
#
# `contract_document` answers a `SiteSearch::Document` of a record of its
# own (a new record id and copy id on every call) with those words in its
# title, body and code fields, in `language`, shown from `shown_from` (nil:
# a moment before now) until `shown_until`. A backend that keeps nothing
# but what it is handed (an engine outside the CMS, `SiteSearch::Fake`)
# includes `SiteSearchBackendContract::BareDocuments`, which builds the
# value alone; one that reads the site's own tables (the built-in) defines
# its own, making the record live with a copy so the document is real.
#
# The words are ones a stemmer leaves whole, so a backend's language
# analysis finds the word as typed and marks it in the snippet.
#
# A GEM'S TEST REACHES IT BY PATH, from a checkout of the ContentSpiel it
# runs against (`CONTENTSPIEL_ROOT`): this file is that path's promise,
# `test/support/site_search_backend_contract.rb` under the CMS's root, and
# needs nothing of this suite's helpers, only the application booted in the
# test environment and Active Support's test case. `config/boot.rb` sets up
# the bundle of `BUNDLE_GEMFILE`, the CMS's own unless it is set, so the
# gem's test Gemfile holds the CMS's gems and the gem's:
#
#   # Gemfile, in the gem's root, with BUNDLE_GEMFILE pointing at it
#   eval_gemfile File.join(ENV.fetch("CONTENTSPIEL_ROOT"), "Gemfile")
#   gemspec
#
#   # the gem's contract test, run with SEARCH_BACKEND=acme/solr
#   ENV["RAILS_ENV"] = "test"
#   require File.join(ENV.fetch("CONTENTSPIEL_ROOT"), "config/environment")
#   require "active_support/test_case"
#   require Rails.root.join("test/support/site_search_backend_contract").to_s
#
#   class Acme::SolrBackendTest < ActiveSupport::TestCase
#     include SiteSearchBackendContract
#     include SiteSearchBackendContract::BareDocuments
#     def backend = SiteSearch::Backends.current
#   end
#
# The boot's `Bundler.require` loads the gem, whose file calls the hook
# (`ContentSpiel::Plugins.search_backends`), before the registries are
# filled, as in a site.
#
# So the file stays here, requires nothing, and names no helper of
# test/support; moving or renaming it, or a contract test a backend that
# obeys `SiteSearch::Backend` cannot pass, is a breaking change for every
# gem (test/lib/site_search_backend_contract_test.rb runs it the way a gem
# does, in a process of its own).
module SiteSearchBackendContract
  extend ActiveSupport::Concern

  # Builds a document of a record that exists nowhere, for a backend that
  # holds only what it is handed.
  module BareDocuments
    def contract_document(title:, body: "", code: "", language: "en", shown_from: nil, shown_until: nil)
      @contract_ids = (@contract_ids || 0) + 1
      record_id = 900_000 + @contract_ids
      copy_id = 800_000 + @contract_ids
      fields = [
        SiteSearch::Field.new(name: "title", weight: :a, text: title),
        SiteSearch::Field.new(name: "summary", weight: :b, text: ""),
        SiteSearch::Field.new(name: "body", weight: :c, text: body),
        SiteSearch::Field.new(name: "code", weight: :d, text: code)
      ]
      shown_from ||= 1.day.ago
      SiteSearch::Document.new(
        key: [ "Page", record_id, copy_id, language ].join(":"), record_type: "Page", record_id: record_id, copy_id: copy_id,
        language: language, url: "/contract/#{record_id}", live_at: shown_from, shown_from: shown_from, shown_until: shown_until,
        fields: fields, text: body
      )
    end
  end

  def contract_now = @contract_now ||= Time.current.change(usec: 0)

  def contract_deadline(seconds = 3) = contract_clock + seconds

  def contract_clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  # A deadline no contract search comes near.
  def far_deadline = contract_deadline

  def contract_query(text, language: "en", page: 1, per_page: SiteSearch::Query::PER_PAGE, now: contract_now, close_matches: true)
    SiteSearch::Query.new(text: text, language: language, page: page, per_page: per_page, now: now, close_matches: close_matches)
  end

  def contract_search(text, **options)
    backend.search(contract_query(text, **options), deadline: far_deadline).tap { |results| assert_kind_of SiteSearch::Results, results }
  end

  def index_documents(*documents) = backend.index(documents)

  def contract_keys(text, **options) = contract_search(text, **options).hits.map { |hit| hit_key(hit) }

  def hit_key(hit) = [ hit.record_type, hit.record_id, hit.copy_id, hit.language ].join(":")

  included do
    setup { backend.clear }

    test "contract: a document is found by a word of each field" do
      document = contract_document(title: "Albatross", body: "the glacier melts", code: "kubectl apply")
      backend.index([ document ])

      %w[albatross glacier kubectl].each do |word|
        results = contract_search(word)
        assert_equal [ document.key ], results.hits.map { |hit| hit_key(hit) }, word
        assert_equal 1, results.total, word
        hit = results.hits.first
        assert_equal [ document.record_type, document.record_id, document.copy_id, document.language ],
          [ hit.record_type, hit.record_id, hit.copy_id, hit.language ]
        assert_kind_of SiteSearch::Snippet, hit.snippet
        assert_kind_of Numeric, hit.rank
      end
      assert_empty contract_search("walrus").hits
    end

    test "contract: the title outranks the body" do
      in_body = contract_document(title: "Harbour notes", body: "a kayak on the water")
      in_title = contract_document(title: "Kayak", body: "water")
      backend.index([ in_body, in_title ])

      hits = contract_search("kayak").hits
      assert_equal [ in_title.key, in_body.key ], hits.map { |hit| hit_key(hit) }
      assert_operator hits.first.rank, :>, hits.last.rank
    end

    test "contract: index with the same key replaces" do
      document = contract_document(title: "Albatross")
      backend.index([ document ])
      backend.index([ document.with(fields: document.fields.map { |field| field.name == "title" ? field.with(text: "Pelican") : field }) ])

      assert_empty contract_search("albatross").hits
      assert_equal [ document.key ], contract_keys("pelican")
      assert_equal 1, contract_search("pelican").total
    end

    test "contract: remove by copy and by record" do
      one = contract_document(title: "Albatross one")
      two = contract_document(title: "Albatross two")
      german = contract_document(title: "Albatross drei", language: "de")
      backend.index([ one, two, german ])

      backend.remove(record_type: one.record_type, record_id: one.record_id, copy_ids: [ one.copy_id + 1 ])
      assert_equal [ one.key, two.key ].sort, contract_keys("albatross").sort, "another copy's id removes nothing"
      backend.remove(record_type: one.record_type, record_id: one.record_id, copy_ids: [ one.copy_id ])
      assert_equal [ two.key ], contract_keys("albatross")

      backend.remove(record_type: two.record_type, record_id: two.record_id)
      assert_empty contract_search("albatross").hits

      backend.remove(record_type: german.record_type, record_id: german.record_id, languages: %w[en])
      assert_equal [ german.key ], contract_keys("albatross", language: "de"), "another language's removal leaves it"
      backend.remove(record_type: german.record_type, record_id: german.record_id, languages: %w[de])
      assert_empty contract_search("albatross", language: "de").hits
    end

    test "contract: prune_record keeps the listed copies and with none forgets the record" do
      one = contract_document(title: "Albatross one")
      two = contract_document(title: "Albatross two")
      backend.index([ one, two ])

      backend.prune_record(record_type: one.record_type, record_id: one.record_id, except_copy_ids: [ one.copy_id ])
      assert_equal [ one.key, two.key ].sort, contract_keys("albatross").sort, "the listed copy stays"
      backend.prune_record(record_type: one.record_type, record_id: one.record_id, except_copy_ids: [ one.copy_id + 1_000 ])
      assert_equal [ two.key ], contract_keys("albatross"), "a copy not listed goes"

      backend.index([ one ])
      backend.prune_record(record_type: one.record_type, record_id: one.record_id, except_copy_ids: [])
      assert_equal [ two.key ], contract_keys("albatross"), "an empty list forgets the record, and only it"
    end

    test "contract: clear forgets everything" do
      backend.index([ contract_document(title: "Albatross"), contract_document(title: "Albatross", language: "de") ])
      backend.clear
      assert_empty contract_search("albatross").hits
      assert_empty contract_search("albatross", language: "de").hits
    end

    test "contract: a document is out of view before shown_from and from shown_until" do
      from = contract_now + 1.hour
      document = contract_document(title: "Albatross", shown_from: from, shown_until: from + 1.hour)
      open = contract_document(title: "Albatross open", shown_from: from)
      backend.index([ document, open ])

      assert_empty contract_search("albatross", now: from - 1.second).hits
      assert_equal [ document.key, open.key ].sort, contract_keys("albatross", now: from).sort
      assert_equal [ document.key, open.key ].sort, contract_keys("albatross", now: from + 1.hour - 1.second).sort
      assert_equal [ open.key ], contract_keys("albatross", now: from + 1.hour)
      assert_equal [ open.key ], contract_keys("albatross", now: from + 1.year), "no shown_until is shown for good"
    end

    test "contract: one language's query never finds another's document" do
      english = contract_document(title: "Albatross")
      german = contract_document(title: "Albatross", language: "de")
      backend.index([ english, german ])

      assert_equal [ english.key ], contract_keys("albatross")
      assert_equal [ german.key ], contract_keys("albatross", language: "de")
      assert_empty contract_search("albatross", language: "es").hits
    end

    test "contract: page and per_page cut the hits and the total counts them all" do
      documents = 3.times.map { |index| contract_document(title: "Albatross #{%w[one two three][index]}") }
      backend.index(documents)

      first = contract_search("albatross", page: 1, per_page: 2)
      second = contract_search("albatross", page: 2, per_page: 2)
      past = contract_search("albatross", page: 3, per_page: 2)
      assert_equal [ 2, 1, 0 ], [ first, second, past ].map { |results| results.hits.size }
      assert_equal [ 3, 3, 3 ], [ first, second, past ].map(&:total)
      assert_equal documents.map(&:key).sort, (first.hits + second.hits).map { |hit| hit_key(hit) }.sort
    end

    test "contract: a snippet's marks fall inside its text on the query's words" do
      backend.index([ contract_document(title: "Shore", body: "Along the shore a Lighthouse stands; the lighthouse keeper waits by the lighthouse.") ])

      snippet = contract_search("lighthouse").hits.first.snippet
      assert_kind_of String, snippet.text
      assert_not_empty snippet.marks
      snippet.marks.each do |(start, length)|
        assert_operator start, :>=, 0
        assert_operator start + length, :<=, snippet.text.length
        assert_includes snippet.text[start, length].downcase, "lighthouse"
      end
    end

    # The text is a visitor's, handed over as typed (normalised, at most
    # `SiteSearch::Query::MAX_LENGTH` characters), never a query in the
    # engine's own language (`SiteSearch::Backend`): an engine whose client
    # takes a query syntax (Solr's or Lucene's parsers, Elasticsearch's
    # `query_string`) escapes it, or sends the words as plain text, so a
    # field name, an operator, a boost or a wildcard is no instruction to
    # it. A backend may raise on any of them (the caller scrubs and reports
    # it, and the block says search is unavailable); what it answers holds
    # no document that lacks the plain words, and syntax alone, which has
    # no words, finds nothing.
    test "contract: a query full of an engine's syntax is words, never an instruction" do
      albatross = contract_document(title: "Albatross", body: "the glacier melts")
      backend.index([ albatross, contract_document(title: "Pelican") ])

      [
        'title:albatross AND (glacier OR walrus)^2 ~ * ? "[',
        "+albatross -walrus || !glacier && {a TO z} [* TO *]",
        'albatross" OR "1"="1',
        "albatross\\ /glac.*/ ((( ))) ^ ~2 \\",
        "albatross} ] ) ; DROP TABLE search_entries; --",
        "_query_:{!lucene}albatross {!xmlparser v='<x/>'}",
        "albatross" + " OR walrus" * 40
      ].each do |raw|
        text = SiteSearch::Query.normalise(raw).first(SiteSearch::Query::MAX_LENGTH)
        begin
          results = contract_search(text)
        rescue StandardError
          next
        end
        assert_kind_of Array, results.hits, raw
        assert_kind_of Integer, results.total, raw
        assert_operator results.total, :>=, results.hits.size, raw
        assert_empty results.hits.map { |hit| hit_key(hit) } - [ albatross.key ], "#{raw} found a document without its plain words"
      end

      [ "*:*", "*", "?", "id:*", "{!lucene}*:*", "\"\"", "()" ].each do |raw|
        begin
          results = contract_search(raw)
        rescue StandardError
          next
        end
        assert_empty results.hits, "#{raw} is no query for every document"
      end
    end

    test "contract: search answers or raises by the deadline" do
      backend.index([ contract_document(title: "Albatross") ])
      query = SiteSearch::Query.new(text: "albatross", language: "en", page: 1, per_page: 10, now: contract_now)
      start = contract_clock
      deadline = start + 0.5
      begin
        backend.search(query, deadline: deadline)
      rescue StandardError
        nil
      end
      assert_operator contract_clock - start, :<=, deadline - start + 0.2
    end

    # A backend may add close matches (a word one typo away) when
    # `close_matches` is true, by its own rule; one that adds none passes.
    # Every exact hit comes first, and a verifying search
    # (`close_matches: false`) is answered exact.
    test "contract: a close hit never stands before an exact hit, and close_matches: false answers no close hit" do
      index_documents(contract_document(title: "deployment guide"), contract_document(title: "deploymnet notes"))
      hits = backend.search(contract_query("deploymnet"), deadline: far_deadline).hits
      first_close = hits.index(&:close) || hits.size
      assert hits.drop(first_close).all?(&:close)
      refute backend.search(contract_query("deploymnet", close_matches: false), deadline: far_deadline).hits.any?(&:close)
    end

    test "contract: a correction is plain text no longer than MAX_LENGTH, or nil" do
      index_documents(contract_document(title: "deployment"))
      correction = backend.search(contract_query("deploymnet"), deadline: far_deadline).correction
      assert correction.nil? || (correction.is_a?(String) && correction.length <= SiteSearch::Query::MAX_LENGTH)
    end

    test "contract: health answers within the deadline" do
      start = contract_clock
      deadline = start + 1
      health = backend.health(deadline: deadline)
      assert_operator contract_clock - start, :<=, deadline - start + 0.2
      assert_kind_of SiteSearch::Health, health
      assert_includes %i[ok warn failed], health.status
      assert(health.detail.nil? || health.detail.is_a?(String))
    end
  end
end
