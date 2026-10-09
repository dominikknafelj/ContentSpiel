require "test_helper"

class Notes::ThreadStateTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing")
    @thread = as(users(:two)) { Notes::Start.call(@page, body: "Is this right, @[#{users(:reader).id}]?") }.record
    @stranger = User.create!(email_address: "stranger@example.com", password: "a-long-password-1")
  end

  def last_actions(count) = Audit::Event.order(:id).last(count).map(&:action)

  test "a reader resolves: the state, who and when, the followers told, one event" do
    result = as(users(:reader)) { Notes::Resolve.call(@thread) }

    assert result.ok?, result.errors.to_sentence
    assert_equal [ "resolved", users(:reader).id ], [ @thread.reload.state, @thread.resolved_by_id ]
    assert_not_nil @thread.resolved_at
    # The reader's own mention row stays as it was; the other follower is told.
    assert_equal [ [ users(:reader).id, "mention" ], [ users(:two).id, "resolved" ] ].sort, Notes::Delivery.pluck(:user_id, :reason).sort
    event = Audit::Event.order(:id).last
    assert_equal [ "note.resolved", "Page", @page.id, { "thread_id" => @thread.id } ], [ event.action, event.subject_type, event.subject_id, event.metadata ]
    assert_nil event.snapshot
  end

  # Review Focus 1, through the service: the mentioned person already has a row on the first message.
  test "a resolve by someone else reuses the mentioned person's row" do
    assert as(users(:two)) { Notes::Resolve.call(@thread) }.ok?

    assert_equal [ [ users(:reader).id, "resolved" ] ], Notes::Delivery.pluck(:user_id, :reason)
  end

  test "resolving twice is one event; the second is a success that changes nothing" do
    as(users(:reader)) { Notes::Resolve.call(@thread) }
    stamp = @thread.reload.resolved_at

    assert_no_difference -> { Audit::Event.count } do
      assert as(users(:two)) { Notes::Resolve.call(Notes::Thread.find(@thread.id)) }.ok?
    end
    assert_equal [ stamp, users(:reader).id ], [ @thread.reload.resolved_at, @thread.resolved_by_id ]
  end

  test "reopen clears the resolve and tells the followers" do
    as(users(:two)) { Notes::Resolve.call(@thread) }

    assert as(users(:two)) { Notes::Reopen.call(@thread) }.ok?
    assert_equal [ "open", nil, nil ], @thread.reload.then { |thread| [ thread.state, thread.resolved_at, thread.resolved_by_id ] }
    assert_equal [ [ users(:reader).id, "reopened" ] ], Notes::Delivery.pluck(:user_id, :reason)
    assert_equal %w[note.resolved note.reopened], last_actions(2)
  end

  test "pin and unpin need the edit right; a reader is refused" do
    refused = as(users(:reader)) { Notes::Pin.call(@thread) }
    assert_predicate refused, :denied?
    assert_equal "pages.edit", Audit::Event.order(:id).last.metadata["permission"]

    assert as(users(:two)) { Notes::Pin.call(@thread) }.ok?
    assert_equal [ true, users(:two).id ], [ @thread.reload.pinned, @thread.pinned_by_id ]
    assert as(users(:two)) { Notes::Unpin.call(@thread) }.ok?
    assert_equal [ false, nil, nil ], @thread.reload.then { |thread| [ thread.pinned, thread.pinned_at, thread.pinned_by_id ] }
    assert_equal %w[note.pinned note.unpinned], last_actions(2)
  end

  test "a pinned thread is always open: resolving it unpins it, and a resolved thread can't be pinned" do
    as(users(:two)) { Notes::Pin.call(@thread) }

    assert as(users(:reader)) { Notes::Resolve.call(@thread) }.ok?
    assert_equal [ "resolved", false, nil, nil ], @thread.reload.then { |thread| [ thread.state, thread.pinned, thread.pinned_at, thread.pinned_by_id ] }
    assert_equal "note.resolved", Audit::Event.order(:id).last.action

    assert_equal [ "Reopen this note before pinning it." ], as(users(:two)) { Notes::Pin.call(@thread) }.errors
    assert_equal [ "resolved", false ], [ @thread.reload.state, @thread.pinned ]
  end

  test "a stranger is refused each of them, and a thread that is gone is a failure" do
    [ Notes::Resolve, Notes::Reopen, Notes::Pin, Notes::Unpin ].each do |service|
      assert_predicate as(@stranger) { service.call(@thread) }, :denied?, service.name
    end
    stale = Notes::Thread.find(@thread.id)
    @thread.destroy!

    assert_equal [ "This note is gone: it was deleted, or what it was on was." ], as(users(:two)) { Notes::Resolve.call(stale) }.errors
  end

  test "none of them writes the page" do
    before = [ @page.reload.updated_at, PublicSite::Version.current ]

    as(users(:two)) { [ Notes::Pin, Notes::Unpin, Notes::Resolve, Notes::Reopen ].each { |service| assert service.call(@thread).ok? } }

    assert_equal before, [ @page.reload.updated_at, PublicSite::Version.current ]
  end

  # One rule for every notes write on an existing thread: a container in the
  # trash reads as gone under its lock, so none of them runs beside
  # `Trash::Purge` (`Notes::Authorization#lock_container`).
  test "on a page in the trash each of them is the ordinary failure, and writes nothing" do
    as(users(:two)) { Notes::Pin.call(@thread) }
    @page.update!(trashed_at: Time.current)
    before = @thread.reload.attributes

    [ Notes::Resolve, Notes::Unpin ].each do |service|
      assert_no_difference [ -> { Notes::Delivery.count }, -> { Audit::Event.count } ], service.name do
        result = as(users(:two)) { service.call(@thread) }
        assert_equal [ "This note is gone: it was deleted, or what it was on was." ], result.errors, service.name
        assert_not_predicate result, :denied?, service.name
      end
    end
    assert_equal before, @thread.reload.attributes
  end

  test "on a page in the trash a resolved thread is not reopened and an open one is not pinned" do
    resolved = as(users(:two)) { Notes::Start.call(@page, body: "Done already") }.record
    as(users(:two)) { Notes::Resolve.call(resolved) }
    @page.update!(trashed_at: Time.current)

    assert_no_difference [ -> { Notes::Delivery.count }, -> { Audit::Event.count } ] do
      assert_equal [ "This note is gone: it was deleted, or what it was on was." ], as(users(:two)) { Notes::Reopen.call(resolved) }.errors
      assert_equal [ "This note is gone: it was deleted, or what it was on was." ], as(users(:two)) { Notes::Pin.call(@thread) }.errors
    end
    assert_equal [ "resolved", false ], [ resolved.reload.state, @thread.reload.pinned ]
  end

  # In the order that makes each one write: pin, unpin, resolve, reopen.
  test "each of them locks the page's row before it reads or writes a notes row" do
    [ Notes::Pin, Notes::Unpin, Notes::Resolve, Notes::Reopen ].each do |service|
      fresh = Notes::Thread.find(@thread.id)
      statements = capture_sql { assert as(users(:two)) { service.call(fresh) }.ok? }
      lock = statements.index { |sql| sql.include?(%(FROM "pages")) && sql.include?("FOR UPDATE") }
      notes = statements.index { |sql| sql.include?(%("note_)) }

      assert lock && notes, "#{service}\n#{statements.join("\n")}"
      assert_operator lock, :<, notes, service.name
      assert statements.any? { |sql| sql.start_with?(%(UPDATE "note_threads")) }, "#{service} wrote nothing"
    end
  end
end
