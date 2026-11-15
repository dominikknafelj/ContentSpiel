require "test_helper"

# The built-in's vocabulary (search 2 spec §3.2, §12.x): the words of a
# document's title, tags, summary and body, written beside its entry and in
# its transaction, never a stopword of its language, and pruned to the words
# some entry of their language still holds.
class SiteSearch::Postgres::VocabularyTest < ActiveSupport::TestCase
  setup do
    @copy = Publishing.current(create_page(title: "Vocabulary host"))
    SiteSearch::Word.delete_all # version: none (each test reads a vocabulary of its own documents)
  end

  def backend = SiteSearch::Postgres.new

  # A document of the host page's copy in `language`, whose fields are these.
  def doc(title:, body: "", code: "", summary: "", language: "en")
    fields = [
      SiteSearch::Field.new(name: "title", weight: :a, text: title),
      SiteSearch::Field.new(name: "summary", weight: :b, text: summary),
      SiteSearch::Field.new(name: "body", weight: :c, text: body),
      SiteSearch::Field.new(name: "code", weight: :d, text: code)
    ]
    SiteSearch::Document.new(key: "Page:#{@copy.record_id}:#{@copy.id}:#{language}", record_type: "Page", record_id: @copy.record_id,
      copy_id: @copy.id, language: language, url: nil, live_at: @copy.live_at, shown_from: @copy.live_at, shown_until: nil,
      fields: fields, text: body)
  end

  def index(*documents) = backend.index(documents)

  def words(locale = "en") = SiteSearch::Word.where(locale: locale).order(:word).pluck(:word)

  test "a word is letters, marks and digits with an inner apostrophe, lowercased, 4 to 32 long, not digits alone" do
    words = SiteSearch::Postgres::Vocabulary.words_of(doc(title: "Straße don't 2026 abc Ünïcode #{"x" * 33}", body: "Deployment, deployment."))
    assert_equal %w[deployment don't straße ünïcode], words.sort
  end

  test "the words come from the title, the tags, the summary and the body" do
    document = doc(title: "Lighthouse", summary: "keeper", body: "foghorn")
    tagged = document.with(fields: document.fields + [ SiteSearch::Field.new(name: "tags", weight: :a, text: "seafaring") ])
    assert_equal %w[foghorn keeper lighthouse seafaring], SiteSearch::Postgres::Vocabulary.words_of(tagged).sort
  end

  test "code is never in the vocabulary" do
    index(doc(title: "Listing", code: "kubectlapply"))
    assert_equal %w[listing], words
    assert_not SiteSearch::Word.exists?(word: "kubectlapply")
  end

  # Measured on Postgres 17: `to_tsvector('english', …)` is empty for
  # "these", "which" and "don't", and not for "would", which the English
  # list does not hold.
  test "stopwords stay out of the vocabulary" do
    index(doc(title: "these which don't would albatross", language: "en"))
    assert_equal %w[albatross would], words("en")
  end

  test "a stopword of one language is a word of another" do
    index(doc(title: "these albatross", language: "en"), doc(title: "these albatross", language: "de"))
    assert_equal %w[albatross], words("en")
    assert_equal %w[albatross these], words("de")
  end

  # Postgres keeps `example.com` and `info@example.org` as one lexeme each,
  # so no entry holds `example` by the prune's test, and the writer keeps
  # it out by the same test.
  test "a word inside a host name or e-mail address never enters" do
    index(doc(title: "visit example.com", body: "mail info@example.org"))
    assert_equal %w[mail visit], words
    assert_equal 0, SiteSearch::Postgres::Vocabulary.prune, "the prune finds nothing the writer kept that no entry holds"
  end

  # The advisory locks the current connection holds, by mode.
  def vocabulary_locks
    classid, objid = SiteSearch::Postgres::Vocabulary::LOCK
    SiteSearch::Word.connection.select_values(SiteSearch::Word.sanitize_sql_array([
      "SELECT mode FROM pg_locks WHERE locktype = 'advisory' AND pid = pg_backend_pid() AND classid = ? AND objid = ? AND objsubid = 2", classid, objid
    ])).sort
  end

  test "a write takes the vocabulary's lock shared and a prune takes it exclusive, each to the transaction's end" do
    SiteSearch::Entry.transaction(requires_new: true) do
      index(doc(title: "albatross"))
      assert_equal %w[ShareLock], vocabulary_locks, "a write in flight lets other writes through and holds a prune"
    end
    SiteSearch::Entry.transaction(requires_new: true) do
      SiteSearch::Postgres::Vocabulary.prune
      assert_includes vocabulary_locks, "ExclusiveLock", "a prune holds every write"
    end
  end

  test "the four limited languages get no vocabulary" do
    index(doc(title: "検索エンジンの使い方 searching", language: "ja"))
    assert_empty SiteSearch::Word.where(locale: "ja")
  end

  test "a word already in the vocabulary is left as it is, and a text that looks like SQL is a word" do
    index(doc(title: "albatross"))
    index(doc(title: "Albatross {quay}, \"harbour\" back\\slash it's"))
    assert_equal %w[albatross back harbour quay slash], words
  end

  # Two writers that insert the same new words in different orders would
  # each wait on the other's uncommitted unique-index entries: a deadlock.
  # Written in one order everywhere, the second waits for the first.
  test "the words are inserted in their sorted order, whatever order the text holds them in" do
    inserts = []
    ActiveSupport::Notifications.subscribed(->(*, payload) { inserts << payload[:sql] if payload[:sql].start_with?("INSERT INTO \"search_words\"") }, "sql.active_record") do
      index(doc(title: "zephyr mango apple", body: "kestrel bramble"))
    end
    found = %w[apple bramble kestrel mango zephyr].map { |word| inserts.sole.index("'#{word}'") }
    assert_equal found.sort, found, inserts.sole
  end

  test "the words are written in the entry's transaction and go with its rollback" do
    SiteSearch::Entry.transaction(requires_new: true) do
      index(doc(title: "rollbackword"))
      assert_equal %w[rollbackword], words
      raise ActiveRecord::Rollback
    end
    assert_empty words
  end

  test "the prune deletes the words no entry of their language holds and keeps the rest" do
    index(doc(title: "Lighthouse deployments"))
    SiteSearch::Word.insert_all([ { locale: "en", word: "orphanword" }, { locale: "de", word: "lighthouse" } ]) # version: none (a test plants stale words)

    assert_equal 2, SiteSearch::Postgres::Vocabulary.prune
    assert_equal %w[deployments lighthouse], words("en"), "a word is held through its stem"
    assert_empty words("de"), "a word is held only by an entry of its own language"
  end

  test "a build ends with no word that no entry holds" do
    SiteSearch::Word.insert_all([ { locale: "en", word: "orphanword" } ]) # version: none (a test plants a stale word)
    SiteSearch::Rebuild.new(name: "postgres", backend: backend).call
    assert_not SiteSearch::Word.exists?(word: "orphanword")
    assert_includes words, "vocabulary", "the build wrote the words of the entries it indexed"
  end

  test "clearing the built-in clears its vocabulary" do
    index(doc(title: "albatross"))
    backend.clear
    assert_empty SiteSearch::Word.all
  end

  test "the entry keeps its title's text" do
    index(doc(title: "Lighthouse keeper"))
    assert_equal "Lighthouse keeper", SiteSearch::Entry.find_by!(published_version_id: @copy.id, locale: "en").title
  end
end
