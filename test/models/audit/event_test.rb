require "test_helper"

# `Audit::Event`'s append-only guarantee (access-control design spec §4.1),
# at both the model and the database level, and its query scopes.
class Audit::EventTest < ActiveSupport::TestCase
  setup do
    Current.actor = users(:one)
    Current.channel = :admin
    @event = Audit.record("post.updated", subject: create_post(title: "Immutable"), field_changes: { "en title" => [ "a", "b" ] })
  end

  test "the append-only trigger exists in the test database" do
    # schema.rb can't carry triggers -- this proves the post-schema-load hook
    # (config/initializers/db_triggers.rb) put it there anyway.
    count = ActiveRecord::Base.connection.select_value(<<~SQL)
      SELECT COUNT(*) FROM pg_trigger
      WHERE tgname = 'audit_events_append_only' AND tgrelid = 'audit_events'::regclass AND NOT tgisinternal
    SQL

    assert_equal 1, count
  end

  test "destroy is refused by the model" do
    assert_not @event.destroy
    assert Audit::Event.exists?(@event.id)
    assert_raises(ActiveRecord::RecordNotDestroyed) { @event.destroy! }
  end

  test "updating a frozen column is refused by the model" do
    assert_raises(ActiveRecord::ReadOnlyRecord) { @event.update!(action: "post.deleted") }
    assert_equal "post.updated", @event.reload.action
  end

  test "a raw DELETE is refused by the database" do
    assert_raises(ActiveRecord::StatementInvalid) { Audit::Event.where(id: @event.id).delete_all }
  end

  test "a raw UPDATE of action is refused by the database" do
    assert_raises(ActiveRecord::StatementInvalid) { Audit::Event.where(id: @event.id).update_all(action: "post.deleted") }
  end

  test "a raw UPDATE of any other frozen column is refused by the database" do
    assert_raises(ActiveRecord::StatementInvalid) { Audit::Event.where(id: @event.id).update_all(user_id: users(:two).id) }
  end

  test "the coalescing columns may be updated" do
    later = 5.minutes.from_now

    Audit::Event.where(id: @event.id).update_all(last_occurred_at: later, snapshot: { "v" => 2 }, field_changes: {})

    @event.reload
    assert_in_delta later, @event.last_occurred_at, 1.second
    assert_equal({ "v" => 2 }, @event.snapshot)
  end

  # Media library Task 1 renamed `MediaAsset` to `Media::Asset`; a row
  # recorded before that still stores the legacy class name in
  # `subject_type`/`actor_type`, and this table can never rewrite it
  # (append-only). `polymorphic_class_for`'s own override is what keeps
  # `event.subject`/`event.actor` resolving such a row instead of raising
  # `NameError` for a constant that no longer exists.
  test "polymorphic_class_for maps the legacy MediaAsset type to Media::Asset" do
    assert_equal Media::Asset, Audit::Event.polymorphic_class_for("MediaAsset")
    assert_equal Media::Asset, Audit::Event.polymorphic_class_for("Media::Asset")
  end

  test "subject resolves for a legacy MediaAsset-typed row instead of raising" do
    asset = create_media_asset
    legacy_event = Audit::Event.create!(action: "media.uploaded", subject_type: "MediaAsset", subject_id: asset.id,
      subject_label: "Media asset ##{asset.id}", channel: "admin", occurred_at: Time.current, last_occurred_at: Time.current)

    assert_equal asset, legacy_event.subject
  end

  test "scopes: for_subject and by_user" do
    other_post = create_post(title: "Other")
    travel 1.minute do
      Current.actor = users(:two)
      @newer = Audit.record("post.published", subject: other_post)
    end

    # `create_post` goes through `Posts::Save`, which records its own
    # `post.created`/`post.published` -- only this test's own events count.
    ours = Audit::Event.where(id: [ @event.id, @newer.id ])
    assert_equal [ @event ], ours.for_subject(@event.subject).to_a
    assert_equal [ @newer ], Audit::Event.by_user(users(:two)).to_a
  end

  # The log's order is (last_occurred_at, id); Older/Newer on the event page
  # walk it with these two.
  test "older_in_log_than and newer_in_log_than split the log around an event, ties broken by id" do
    at = Time.zone.parse("2026-03-01 12:00:00")
    make = ->(time) { Audit::Event.create!(action: "test.order", channel: "admin", occurred_at: time, last_occurred_at: time) }
    before = make.(at - 1.minute)
    tie_low, middle, tie_high = make.(at), make.(at), make.(at)
    after = make.(at + 1.minute)
    log = Audit::Event.where(action: "test.order")

    assert_equal [ before, tie_low ].sort_by(&:id), log.older_in_log_than(middle).order(:id).to_a
    assert_equal [ tie_high, after ].sort_by(&:id), log.newer_in_log_than(middle).order(:id).to_a
    assert_not_includes log.older_in_log_than(middle).or(log.newer_in_log_than(middle)), middle
    assert_empty log.older_in_log_than(before)
    assert_empty log.newer_in_log_than(after)
    # The neighbours, as the event page asks for them.
    assert_equal tie_low.id, Audit::Filter.ordered(log.older_in_log_than(middle)).pick(:id)
    assert_equal tie_high.id, log.newer_in_log_than(middle).order(last_occurred_at: :asc, id: :asc).pick(:id)
  end

  test "newest_per_subject keeps one event per subject: the latest recorded, the higher id on a tie" do
    at = Time.zone.parse("2026-03-01 12:00:00")
    make = ->(type, id, time) { Audit::Event.create!(action: "test.newest", channel: "admin", subject_type: type, subject_id: id, occurred_at: time, last_occurred_at: time) }
    make.("Page", 1, at)
    page_newest = make.("Page", 1, at + 1.hour)
    make.("Page", 1, at - 1.hour)
    make.("Post", 1, at)
    post_newest = make.("Post", 1, at)
    other_page = make.("Page", 2, at - 1.day)
    make.("Page", 3, at) # left out by the relation's own condition below

    newest = Audit::Event.where(action: "test.newest").where.not(subject_id: 3).newest_per_subject.to_a

    assert_equal [ page_newest, other_page, post_newest ], newest
    assert_empty Audit::Event.where(action: "test.none").newest_per_subject
  end

  test "occurrences may be updated by the model and by raw SQL, like the coalescing columns" do
    @event.update!(occurrences: 3)
    assert_equal 3, @event.reload.occurrences

    Audit::Event.where(id: @event.id).update_all(occurrences: 4, last_occurred_at: 5.minutes.from_now)
    assert_equal 4, @event.reload.occurrences
  end

  test "actor_label is frozen once written, by the model and by the database" do
    assert_raises(ActiveRecord::ReadOnlyRecord) { @event.update!(actor_label: "Forged") }
    assert_raises(ActiveRecord::StatementInvalid) { Audit::Event.where(id: @event.id).update_all(actor_label: "Forged") }
  end

  test "a raw UPDATE of another column alongside occurrences is still refused" do
    assert_raises(ActiveRecord::StatementInvalid) { Audit::Event.where(id: @event.id).update_all(occurrences: 2, channel: "mcp") }
  end

  test "deleting_block finds the event that took a block away: its own, or the section's that took it along, on that page only" do
    page = create_page(title: "Page")
    other = create_page(title: "Other page")
    block = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }).record
    section = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "section", settings: { "layout" => "two" } }).record
    inside = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text", section_id: section.id, section_column: 1 }).record
    kept = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }).record
    ContentBlocks::Destroy.call(block)
    ContentBlocks::Destroy.call(section)

    assert_equal 1, Audit::Event.deleting_block(block.id, page.id).count
    assert_equal [ "block.deleted" ], Audit::Event.deleting_block(inside.id, page.id).pluck(:action), "the section's event lists the blocks that went with it"
    assert_equal section.id, Audit::Event.deleting_block(inside.id, page.id).first.subject_id
    assert_empty Audit::Event.deleting_block(kept.id, page.id)
    assert_empty Audit::Event.deleting_block(block.id, other.id), "another page's block of the same id is not this one's"
  end
end
