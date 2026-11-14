require "test_helper"

# The built-in backend kept by `SiteSearch::Indexing` (spec §5.4, §6.1): in
# the transaction of the write that changes a copy, so the entries stand or
# fall with it.
class SiteSearch::IndexingTest < ActiveSupport::TestCase
  def entries_of(record) = SiteSearch::Entry.where(record_type: record.class.polymorphic_name, record_id: record.id)

  def copy_ids_of(record) = entries_of(record).distinct.order(:published_version_id).pluck(:published_version_id)

  def found(text, now: Time.current)
    query = SiteSearch::Query.new(text: text, language: "en", page: 1, per_page: 10, now: now)
    SiteSearch::Postgres.new.search(query, deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3).hits.map { |hit| [ hit.record_type, hit.record_id ] }
  end

  test "a copy taken in force is indexed in its transaction and the record's older entries go" do
    page = create_page(title: "Lighthouse")
    first = Publishing.current(page)
    assert_equal [ first.id ], copy_ids_of(page)
    assert_equal Locales.enabled.sort, entries_of(page).pluck(:locale).sort

    assert Pages::Save.call(page.reload, translations: { "en" => { title: "Foghorn" } }).ok?
    publish_changes(page)
    second = Publishing.current(page)

    assert_not_equal first.id, second.id
    assert_equal [ second.id ], copy_ids_of(page), "the older copy's entries are deleted with the new copy in force"
    assert_equal [ [ "Page", page.id ] ], found("foghorn")
    assert_empty found("lighthouse")
  end

  test "a pending copy's entries stand beside the current one's" do
    page = create_page(title: "Lighthouse")
    current = Publishing.current(page)
    assert Pages::Save.call(page.reload, translations: { "en" => { title: "Foghorn" } }).ok?

    publish_changes(page, at: 1.day.from_now)
    pending = Publishing.pending(page)

    assert_equal [ current.id, pending.id ], copy_ids_of(page)
    assert_equal [ [ "Page", page.id ] ], found("lighthouse")
    assert_empty found("foghorn")
    assert_equal [ [ "Page", page.id ] ], found("foghorn", now: 2.days.from_now)

    assert Publishing::CancelScheduledChange.call(page.reload).ok?
    assert_equal [ current.id ], copy_ids_of(page), "a withdrawn copy takes its entries with it"
  end

  test "a rolled-back publish leaves no entry" do
    page = create_page(title: "Lighthouse", published: false)

    Page.transaction do
      assert Pages::Save.call(page.reload, attributes: { published: true }).ok?
      assert_not_empty entries_of(page)
      raise ActiveRecord::Rollback
    end

    assert_empty entries_of(page)
    assert_not copied?(page)
  end

  test "a tag merge rewrites the merged post's entries" do
    blog = create_page(title: "Blog")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: blog), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).ok?
    publish_changes(blog)
    post = create_post(title: "Harbour", tags: [ "seafaring" ])
    assert_equal [ [ "Post", post.id ] ], found("seafaring")

    other = create_post(title: "Quay", tags: [ "maritime" ])

    assert Tags::Merge.call(Tag.find_by!(name: "seafaring"), into: Tag.find_by!(name: "maritime")).ok?

    assert_equal [ [ "Post", other.id ], [ "Post", post.id ] ].sort, found("maritime").sort
    assert_empty found("seafaring")
  end
end
