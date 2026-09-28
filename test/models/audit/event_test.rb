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

  test "scopes: for_subject, by_user and recent" do
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
    assert_equal [ @newer, @event ], ours.recent.to_a
  end
end
