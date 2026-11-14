require "test_helper"

# `search_entries` is derived (spec §6.1, §12): after every write path that
# changes a copy, the table holds what a re-index would write, the
# documents of each record's copy in force and pending copy and nothing
# else. The built-in keeps a trashed or unpublished record's entries (its
# query joins the record's state), so a trash is compared once the record
# is back, and a purge once it is gone.
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

  def assert_parity(step)
    assert_not_empty rows, step
    assert_equal reindexed, rows, "after #{step}, search_entries is what search:reindex would write"
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

    assert delete_for_good(child.reload)
    assert_parity "a page purged"

    ok Tags::Merge.call(Tag.find_by!(name: "seafaring"), into: Tag.find_by!(name: "maritime"))
    assert_parity "a tag merged"
    SiteSearch::Entry.where(record_type: "Post", record_id: post.id, locale: "en").pluck(:document).sole.then { |vector| assert_includes vector, "'maritim'" }
  end
end
