require "test_helper"

# What a visitor's suggestions may name (search 2 spec §11, "Visibility
# holds for every new path"): never a draft, a scheduled record before its
# time, a trashed record, a record under a draft page or another language's
# title, from the built-in or an outside backend's stale index.
class PublicSearchSuggestionsTest < ActionDispatch::IntegrationTest
  def publish(record)
    service = record.is_a?(Page) ? Pages::Save : Posts::Save
    assert service.call(record.reload, attributes: { published: true }).ok? unless record.reload.published_at
    record
  end

  def scheduled_page(title, at:)
    result = Pages::Save.call(attributes: { parent: root_page, published_at: at }, translations: { "en" => { title: title } })
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  def trash(record) = record.tap { assert Trash::Move.call(record.reload).ok? }

  def restore(record) = record.tap { assert Trash::Restore.call(record.reload).ok? }

  def labels_at(now) = SiteSearch.suggest(text: "alba", language: "en", now: now).items.map(&:label).sort

  test "a draft's, a scheduled record's, a trashed record's and a record under a draft page's titles are not suggested, and are once each is live" do
    parent = create_page(title: "Hidden", published: false)
    draft = create_page(title: "Albatross draft", published: false)
    scheduled_page("Albatross scheduled", at: 1.day.from_now)
    trashed = trash(publish(create_page(title: "Albatross trashed")))
    publish(create_page(title: "Albatross under", parent: parent))
    labels = ->(now) { SiteSearch.suggest(text: "alba", language: "en", now: now).items.map(&:label).sort }
    assert_empty labels.(Time.current)
    publish(draft); restore(trashed); publish(parent)
    assert_equal [ "Albatross draft", "Albatross scheduled", "Albatross trashed", "Albatross under" ], labels.(2.days.from_now)
  end

  test "an outside backend's stale index suggests no record a visitor does not see" do
    live = create_page(title: "Albatross live")
    gone = create_page(title: "Albatross gone")
    fake = SiteSearch::Fake.new
    [ live, gone ].each { fake.index(SiteSearch::Documents.for_record(_1, now: Time.current)) }
    trash(gone)
    fake.installed { assert_equal [ "Albatross live" ], labels_at(Time.current) }
  end

  test "a tag that only drafts carry is not suggested" do
    blog = create_page(title: "Blog")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: blog), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).ok?
    assert ContentBlocks::Save.call(ContentBlock.new(owner: blog), attributes: { block_type: "search" }).ok?
    publish_changes(blog)
    draft = create_post(title: "Draft", tags: %w[albatross], published: false)
    assert_empty labels_at(Time.current)
    publish(draft)
    assert_equal %w[albatross], labels_at(Time.current)
  end

  test "a suggestion in German is a German title" do
    page = publish(create_page(title: "Deployment", translations: { "de" => { title: "Bereitstellung" } }))
    assert_equal [ "Bereitstellung" ], SiteSearch.suggest(text: "bereit", language: "de", now: Time.current).items.map(&:label)
    assert_equal [ page.id ], SiteSearch::Postgres.new.suggest(SiteSearch::SuggestQuery.new(text: "bereit", language: "de", now: Time.current, limit: 8),
      deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1).items.map(&:record_id)
    assert_empty SiteSearch.suggest(text: "bereit", language: "en", now: Time.current).items
  end
end
