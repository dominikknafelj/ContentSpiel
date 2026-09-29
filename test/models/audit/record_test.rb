require "test_helper"

# `Audit.record` (access-control design spec §4.2): context from `Current`,
# coalescing, and the transaction/notification contract.
class Audit::RecordTest < ActiveSupport::TestCase
  setup do
    Current.actor = users(:one)
    Current.channel = :admin
    Current.request_id = "req-123"
    Current.ip_address = "203.0.113.7"
  end

  test "records the user actor, channel, request context, label and snapshot" do
    post = create_post(title: "Hello audit")

    event = Audit.record("post.created", subject: post, snapshot: Audit::Snapshot.for(post))

    assert_equal users(:one), event.actor
    assert_equal users(:one).id, event.user_id
    assert_equal "admin", event.channel
    assert_equal "req-123", event.request_id
    assert_equal "203.0.113.7", event.ip
    assert_equal post, event.subject
    assert_equal "Hello audit", event.subject_label
    assert_equal post.id, event.snapshot["id"]
    assert_equal event.occurred_at, event.last_occurred_at
  end

  test "an API token actor is recorded with the token's user as user_id" do
    token, _raw = ApiToken.generate!(users(:two))
    Current.actor = token
    Current.channel = :mcp

    event = Audit.record("post.created", subject: create_post(title: "Via MCP"))

    assert_equal token, event.actor
    assert_equal users(:two).id, event.user_id
    assert_equal "mcp", event.channel
  end

  test "a system actor records no actor or user" do
    Current.actor = nil
    Current.channel = nil

    event = Audit.record("post.created", subject: create_post(title: "Seeded"))

    assert_nil event.actor
    assert_nil event.user_id
    assert_equal "system", event.channel
  end

  test "the event survives the subject's deletion with its label" do
    post = create_post(title: "Short-lived")
    event = Audit.record("post.deleted", subject: post)

    post.destroy!
    event.reload

    assert_nil event.subject
    assert_equal "Short-lived", event.subject_label
    assert_equal [ event ], Audit::Event.where(subject_type: "Post", subject_id: post.id, action: "post.deleted").to_a
  end

  test "two updates by the same actor within the window coalesce into one event" do
    post = create_post(title: "Coalesce me")
    first = Audit.record("post.updated", subject: post, field_changes: { "en title" => [ "A", "B" ] }, snapshot: { "v" => 1 })

    travel 9.minutes do
      second = Audit.record("post.updated", subject: post,
        field_changes: { "en title" => [ "B", "C" ], "en body" => { "digest_before" => "d1", "digest_after" => "d2" } },
        snapshot: { "v" => 2 })

      assert_equal first.id, second.id
    end

    event = first.reload
    assert_equal 1, Audit::Event.for_subject(post).where(action: "post.updated").count
    assert_equal [ "A", "C" ], event.field_changes["en title"]
    assert_equal({ "digest_before" => "d1", "digest_after" => "d2" }, event.field_changes["en body"])
    assert_equal({ "v" => 2 }, event.snapshot)
    assert_operator event.last_occurred_at, :>, event.occurred_at
  end

  test "coalescing keeps the first digest_before and the last digest_after" do
    post = create_post(title: "Bodies")
    first = Audit.record("post.updated", subject: post, field_changes: { "en body" => { "digest_before" => "d1", "digest_after" => "d2" } })
    Audit.record("post.updated", subject: post, field_changes: { "en body" => { "digest_before" => "d2", "digest_after" => "d3" } })

    assert_equal({ "digest_before" => "d1", "digest_after" => "d3" }, first.reload.field_changes["en body"])
  end

  test "the window is measured from last_occurred_at" do
    post = create_post(title: "Rolling window")
    first = Audit.record("post.updated", subject: post)

    travel 8.minutes do
      Audit.record("post.updated", subject: post)
    end
    travel 16.minutes do
      Audit.record("post.updated", subject: post)
    end

    assert_equal [ first.id ], Audit::Event.for_subject(post).where(action: "post.updated").pluck(:id)
  end

  test "updates more than ten minutes apart make two events" do
    post = create_post(title: "Slow edits")
    Audit.record("post.updated", subject: post)

    travel 11.minutes do
      Audit.record("post.updated", subject: post)
    end

    assert_equal 2, Audit::Event.for_subject(post).where(action: "post.updated").count
  end

  test "updates by different actors make two events" do
    post = create_post(title: "Two editors")
    Audit.record("post.updated", subject: post)

    Current.actor = users(:two)
    Audit.record("post.updated", subject: post)

    assert_equal 2, Audit::Event.for_subject(post).where(action: "post.updated").count
  end

  test "updates to different subjects make two events" do
    Audit.record("post.updated", subject: create_post(title: "One"))
    Audit.record("post.updated", subject: create_post(title: "Two"))

    assert_equal 2, Audit::Event.where(action: "post.updated").count
  end

  test "post.published never coalesces" do
    post = create_post(title: "Publish twice", published: false)
    Audit.record("post.published", subject: post)
    Audit.record("post.published", subject: post)

    assert_equal 2, Audit::Event.for_subject(post).where(action: "post.published").count
  end

  test "access.denied coalesces per actor, permission and subject" do
    post = create_post(title: "Forbidden")
    Audit.record("access.denied", subject: post, metadata: { permission: "posts.edit" })
    Audit.record("access.denied", subject: post, metadata: { permission: "posts.edit" })
    Audit.record("access.denied", subject: post, metadata: { permission: "posts.delete" })
    Audit.record("access.denied", subject: create_post(title: "Other"), metadata: { permission: "posts.edit" })
    Current.actor = users(:two)
    Audit.record("access.denied", subject: post, metadata: { permission: "posts.edit" })

    denied = Audit::Event.where(action: "access.denied")
    assert_equal 4, denied.count
    assert_equal 1, denied.for_subject(post).where(actor: users(:one)).where("metadata->>'permission' = ?", "posts.edit").count
  end

  test "access.denied without a subject coalesces per actor and permission" do
    Audit.record("access.denied", metadata: { permission: "settings.manage" })
    Audit.record("access.denied", metadata: { permission: "settings.manage" })

    assert_equal 1, Audit::Event.where(action: "access.denied").count
  end

  test "an event recorded in a transaction that rolls back is gone" do
    post = create_post(title: "Rolled back")

    Post.transaction do
      Audit.record("post.updated", subject: post)
      raise ActiveRecord::Rollback
    end

    assert_empty Audit::Event.for_subject(post).where(action: "post.updated")
  end

  test "the notification fires only after the transaction commits" do
    post = create_post(title: "Notify me")
    received = []
    callback = ->(*, payload) { received << payload[:event] }

    ActiveSupport::Notifications.subscribed(callback, Audit::NOTIFICATION) do
      Post.transaction do
        Audit.record("post.updated", subject: post)
        assert_empty received, "published before commit"
      end

      assert_equal 1, received.size
      assert_equal "post.updated", received.first.action

      Post.transaction do
        Audit.record("post.published", subject: post)
        raise ActiveRecord::Rollback
      end

      assert_equal 1, received.size, "published for a rolled-back event"
    end
  end

  test "a coalesced extension is published too" do
    post = create_post(title: "Notify twice")
    received = []

    ActiveSupport::Notifications.subscribed(->(*, payload) { received << payload[:event] }, "audit.content_spiel") do
      Audit.record("post.updated", subject: post)
      Audit.record("post.updated", subject: post)
    end

    assert_equal 2, received.size
    assert_equal received.first.id, received.last.id
  end

  test "ApplicationService#record_event snapshots the subject" do
    post = create_post(title: "Via a service")
    service = Class.new(ApplicationService) do
      def initialize(post) = @post = post
      def call = record_event("post.updated", subject: @post, field_changes: { "en title" => [ "a", "b" ] }, metadata: { note: "x" })
    end

    event = service.call(post)

    assert_equal "post.updated", event.action
    assert_equal post.id, event.snapshot["id"]
    assert_equal({ "en title" => [ "a", "b" ] }, event.field_changes)
    assert_equal({ "note" => "x" }, event.metadata)
  end

  test "COALESCE_WINDOW is ten minutes" do
    assert_equal 10.minutes, Audit::COALESCE_WINDOW
  end

  # A backstop for Review Focus 5: whoever builds `field_changes` or a
  # snapshot Hash, secrets are dropped before storing -- `metadata` isn't
  # touched (`session.failed` carries an email there by design).
  test "caller-supplied field_changes and snapshots are scrubbed; metadata is not" do
    event = Audit.record("user.updated", subject: users(:two),
      field_changes: { "password_digest" => [ "a", "b" ], "title" => [ "Old", "New" ], "email_address" => [ "x@example.com", "y@example.com" ] },
      snapshot: { "token_digest" => "abc", "name" => "kept" },
      metadata: { "email_address" => "tried@example.com" })

    assert_equal({ "title" => [ "Old", "New" ], "email_address" => [ "x@example.com", "y@example.com" ] }, event.field_changes)
    assert_equal({ "name" => "kept" }, event.snapshot)
    assert_equal({ "email_address" => "tried@example.com" }, event.metadata)
  end

  test "coalescing never replaces a stored snapshot with nil" do
    post = create_post(title: "Keep my snapshot")
    first = Audit.record("post.updated", subject: post, snapshot: { "v" => 1 })
    Audit.record("post.updated", subject: post, field_changes: { "en title" => [ "a", "b" ] })

    assert_equal({ "v" => 1 }, first.reload.snapshot)
    assert_equal [ "a", "b" ], first.field_changes["en title"]
  end
end
