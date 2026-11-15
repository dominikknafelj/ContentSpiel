require "test_helper"

# A purge and a withdrawn copy take their entries with them (the cascade),
# and their words go from the vocabulary in `SiteSearch::PruneWordsJob`,
# enqueued after the commit (search 2 spec §3.2), so a purge removes its
# words within a job's run.
class SiteSearch::PruneWordsJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def ok(result)
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  def trash_and_purge(record)
    ok Trash::Move.call(record.reload)
    ok Trash::Purge.call(record.reload)
  end

  test "one prune runs at a time" do
    assert_equal 1, SiteSearch::PruneWordsJob.concurrency_limit
    assert_equal "site_search_prune_words", SiteSearch::PruneWordsJob.new.concurrency_key.split("/").last
  end

  test "a prune that waits too long for the writes in flight gives up and is tried again" do
    assert SiteSearch::PruneWordsJob.rescue_handlers.any? { |handler, _| handler == "ActiveRecord::LockWaitTimeout" }
    SiteSearch::Word.transaction(requires_new: true) do
      SiteSearch::Postgres::Vocabulary.prune
      assert_equal SiteSearch::Postgres::Vocabulary::LOCK_TIMEOUT, SiteSearch::Word.connection.select_value("SHOW lock_timeout")
    end
  end

  test "a purge outside a run of purges enqueues its own prune" do
    page = create_page(title: "Uniqueword")
    ok Trash::Move.call(page.reload)
    clear_enqueued_jobs
    ok Trash::Purge.call(page.reload)
    assert_enqueued_jobs 1, only: SiteSearch::PruneWordsJob
  end

  test "a run of purges that each commit enqueues one prune when it ends, nested runs as one, a raise after a purge too" do
    pages = 3.times.map { |n| create_page(title: "Runpage #{n}").tap { |page| ok Trash::Move.call(page.reload) } }
    clear_enqueued_jobs

    SiteSearch::Indexing.one_prune do
      ok Trash::Purge.call(pages[0].reload)
      SiteSearch::Indexing.one_prune { ok Trash::Purge.call(pages[1].reload) }
      assert_no_enqueued_jobs only: SiteSearch::PruneWordsJob
    end
    assert_enqueued_jobs 1, only: SiteSearch::PruneWordsJob
    clear_enqueued_jobs

    assert_raises(IOError) do
      SiteSearch::Indexing.one_prune do
        ok Trash::Purge.call(pages[2].reload)
        raise IOError
      end
    end
    assert_enqueued_jobs 1, only: SiteSearch::PruneWordsJob
    clear_enqueued_jobs

    SiteSearch::Indexing.one_prune { nil }
    assert_no_enqueued_jobs only: SiteSearch::PruneWordsJob
  end

  test "a purge's words are pruned by the job after its commit" do
    create_page(title: "Harbourmaster")
    page = create_page(title: "Uniqueword")
    assert SiteSearch::Word.exists?(locale: "en", word: "uniqueword"), "the copy's words were written with its entries"

    trash_and_purge(page)
    assert_enqueued_with(job: SiteSearch::PruneWordsJob)
    assert SiteSearch::Word.exists?(word: "uniqueword"), "the purge itself leaves the words to the job"

    perform_enqueued_jobs
    assert_not SiteSearch::Word.exists?(word: "uniqueword")
    assert SiteSearch::Word.exists?(locale: "en", word: "harbourmaster"), "a word another entry holds stays"
  end

  test "a branch purged together enqueues one prune" do
    root = create_page(title: "Branchroot")
    child = create_page(title: "Branchchild", parent: root)
    create_page(title: "Branchgrandchild", parent: child)
    ok Trash::Move.call(root.reload)
    clear_enqueued_jobs

    ok Trash::Purge.call(root.reload)
    assert_enqueued_jobs 1, only: SiteSearch::PruneWordsJob
    perform_enqueued_jobs
    assert_empty SiteSearch::Word.where(word: %w[branchroot branchchild branchgrandchild])

    other = create_page(title: "Lighthouse")
    ok Trash::Move.call(other.reload)
    clear_enqueued_jobs
    ok Trash::Purge.call(other.reload)
    assert_enqueued_jobs 1, only: SiteSearch::PruneWordsJob # the next transaction asks again
  end

  test "a purge rolled back leaves the next one free to enqueue its prune" do
    page = create_page(title: "Uniqueword")
    ok Trash::Move.call(page.reload)
    clear_enqueued_jobs
    ActiveRecord::Base.transaction(requires_new: true) do
      ok Trash::Purge.call(page.reload)
      raise ActiveRecord::Rollback
    end
    ok Trash::Purge.call(page.reload)
    assert_enqueued_jobs 1, only: SiteSearch::PruneWordsJob
  end

  test "a withdrawn scheduled change's words are pruned by the job" do
    page = create_page(title: "Lighthouse")
    ok Pages::Save.call(page.reload, translations: { "en" => { title: "Scheduledword" } })
    publish_changes(page, at: 1.day.from_now)
    assert SiteSearch::Word.exists?(locale: "en", word: "scheduledword")
    clear_enqueued_jobs

    ok Publishing::CancelScheduledChange.call(page.reload)
    assert_enqueued_with(job: SiteSearch::PruneWordsJob)
    perform_enqueued_jobs
    assert_not SiteSearch::Word.exists?(word: "scheduledword")
    assert SiteSearch::Word.exists?(locale: "en", word: "lighthouse")
  end

  test "a write that is rolled back enqueues no prune" do
    page = create_page(title: "Uniqueword")
    ok Trash::Move.call(page.reload)
    clear_enqueued_jobs

    ActiveRecord::Base.transaction do
      ok Trash::Purge.call(page.reload)
      raise ActiveRecord::Rollback
    end
    assert_no_enqueued_jobs only: SiteSearch::PruneWordsJob
  end
end
