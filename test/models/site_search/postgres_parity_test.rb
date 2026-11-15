require "test_helper"

# `search_entries` is derived (spec §6.1, §12): after every write path that
# changes a copy, the table holds what a re-index would write, the
# documents of each record's copy in force and pending copy. The built-in
# also keeps the entries of a record in the trash or unpublished (its query
# joins the record's state; a re-index writes none for it), and a copy the
# clock superseded keeps its entries until the record's next copy (its
# query skips them). So the rows are compared where neither applies, and
# after a trash or an unpublish the VIEW is: the same hits over the kept
# table as over a fresh re-index.
class SiteSearch::PostgresParityTest < ActiveSupport::TestCase
  # The document too: a merged tag's name is in a post's vector, not in its
  # text.
  COLUMNS = %i[published_version_id locale live_at text document].freeze

  def rows = SiteSearch::Entry.order(*COLUMNS).pluck(*COLUMNS)

  # What a re-index from nothing writes, in a savepoint that is rolled back.
  def reindexed
    fresh = nil
    SiteSearch::Entry.transaction(requires_new: true) do
      backend = SiteSearch::Postgres.new
      backend.clear
      now = Time.current
      (Page.all.to_a + Post.all.to_a).each { |record| backend.index(SiteSearch::Documents.for_record(record, now: now)) }
      fresh = rows
      raise ActiveRecord::Rollback
    end
    fresh
  end

  WORDS = %w[lighthouse foghorn beacon keeper blog harbour quay seafaring maritime home].freeze

  def hits = WORDS.index_with { |word| found(word) }

  def found(word)
    query = SiteSearch::Query.new(text: word, language: "en", page: 1, per_page: 50, now: Time.current)
    SiteSearch::Postgres.new.search(query, deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3).hits
      .map { |hit| [ hit.record_type, hit.record_id, hit.copy_id ] }.sort
  end

  # What a visitor finds over the table as it is, and over a fresh re-index.
  def assert_view_parity(step)
    kept = hits
    fresh = nil
    SiteSearch::Entry.transaction(requires_new: true) do
      backend = SiteSearch::Postgres.new
      backend.clear
      now = Time.current
      (Page.all.to_a + Post.all.to_a).each { |record| backend.index(SiteSearch::Documents.for_record(record, now: now)) }
      fresh = hits
      raise ActiveRecord::Rollback
    end
    assert kept.values.any?(&:present?), step
    assert_equal fresh, kept, "after #{step}, a search over the kept entries finds what it finds over a re-index"
    assert_vocabulary(step)
  end

  def assert_parity(step)
    assert_not_empty rows, step
    assert_equal reindexed, rows, "after #{step}, search_entries is what search:reindex would write"
    assert_vocabulary(step)
  end

  # The documents of every entry's copy and language, built again.
  def current_documents
    now = Time.current
    SiteSearch::Entry.distinct.pluck(:published_version_id, :locale).group_by(&:first).flat_map do |copy_id, pairs|
      languages = pairs.map(&:last)
      SiteSearch::Documents.for(Publishing::Version.find(copy_id), now: now).select { |doc| languages.include?(doc.language) }
    end
  end

  # The words that are no stopword of `language`, asked of Postgres one by
  # one, as the writer's filter is not.
  def non_stopwords(language, words)
    config = SiteSearch::Postgres.config_for(language)
    words.select { |word| SiteSearch::Entry.connection.select_value(SiteSearch::Entry.sanitize_sql_array([ "SELECT to_tsvector(CAST(? AS regconfig), ?) <> ''::tsvector", config, word ])) }
  end

  # A superset: the words of entries that are gone may stay until a prune.
  def assert_vocabulary(step)
    expected = current_documents.flat_map { |doc| non_stopwords(doc.language, SiteSearch::Postgres::Vocabulary.words_of(doc)).map { [ doc.language, it ] } }
    assert_not_empty expected, step
    assert_empty expected - SiteSearch::Word.pluck(:locale, :word), "after #{step}, every non-stopword of every entry is in search_words"
  end

  def ok(result)
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  test "after every write path, the entries are what search:reindex would write" do
    page = create_page(title: "Lighthouse")
    blog = create_page(title: "Blog")
    ok ContentBlocks::Save.call(ContentBlock.new(owner: blog), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } })
    publish_changes(blog)
    post = create_post(title: "Harbour", tags: [ "seafaring" ])
    create_post(title: "Quay", tags: [ "maritime" ])
    assert_parity "a publish"

    ok Pages::Save.call(page.reload, translations: { "en" => { title: "Foghorn" } })
    publish_changes(page, at: 1.day.from_now)
    assert_parity "a change scheduled"

    ok Publishing::CancelScheduledChange.call(page.reload)
    assert_parity "a scheduled change cancelled"

    ok Pages::Save.call(page.reload, translations: { "en" => { title: "Beacon" } })
    publish_changes(page, at: 1.day.from_now)
    ok Publishing::DiscardChanges.call(page.reload)
    assert_parity "changes discarded"

    ok Pages::Save.call(page.reload, translations: { "en" => { slug: "beacon" } })
    publish_changes(page)
    assert_parity "a slug renamed and published"

    child = create_page(title: "Keeper", parent: page)
    ok Pages::Move.call(child.reload, parent: blog.reload, position: 0)
    assert_parity "a page moved"

    ok Trash::Move.call(child.reload)
    ok Trash::Restore.call(child.reload)
    assert_parity "a page trashed and restored"

    ok Pages::Save.call(page.reload, translations: { "en" => { slug: "lantern" } })
    assert_parity "a parent's slug changed, its subpages' addresses moved and their slugs kept"

    ok Posts::Save.call(post.reload, translations: { "en" => { slug: "anchorage" } })
    assert_parity "a live post's slug changed"

    ok Trash::Move.call(child.reload)
    namesake = create_page(title: "Other keeper", parent: blog.reload, translations: { "en" => { title: "Other keeper", slug: child.reload.slug } })
    ok Trash::Restore.call(child.reload)
    assert_not_equal namesake.slug, child.reload.slug, "the restore freed the slug to a suffix"
    assert_parity "a page restored with its slug freed to a suffix"

    ok Trash::Move.call(child.reload)
    assert_view_parity "a page trashed"

    ok Trash::Purge.call(child.reload)
    assert_parity "a page purged"

    ok Pages::Save.call(page.reload, attributes: { published: false })
    assert_view_parity "a page unpublished"

    ok Pages::Save.call(page.reload, attributes: { published: true })
    assert_parity "a page unpublished and published again"
    assert_view_parity "a page unpublished and published again"

    update = create_post(title: "Tide table", content_type: "now_update")
    news = create_page(title: "News")
    ok ContentBlocks::Save.call(ContentBlock.new(owner: news), attributes: { block_type: "post_list", settings: { "content_type" => "now_update" } })
    publish_changes(news)
    assert PublicSite::Urls.new.path_for(update.reload, "en"), "the listing gave the post an address"
    assert_parity "a listing published after its posts"

    ok Tags::Merge.call(Tag.find_by!(name: "seafaring"), into: Tag.find_by!(name: "maritime"))
    assert_parity "a tag merged"
    SiteSearch::Entry.where(record_type: "Post", record_id: post.id, locale: "en").pluck(:document).sole.then { |vector| assert_includes vector, "'maritim'" }
  end
end
