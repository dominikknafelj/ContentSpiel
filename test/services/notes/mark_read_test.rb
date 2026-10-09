require "test_helper"

class Notes::MarkReadTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing")
    @post = create_post(title: "Hello")
    mention = "Look, @[#{users(:reader).id}] and @[#{users(:author).id}]"
    AccessControl::Grant.find_or_create_by!(group: access_control_groups(:author), permission: "pages.read") { |grant| grant.scope = {} }
    as(users(:two)) do
      Notes::Start.call(@page, body: mention)
      Notes::Start.call(@post, body: "And here, @[#{users(:reader).id}]")
    end
  end

  def unread(user) = Notes::Delivery.unread.where(user: user).count

  test "one record's deliveries are read, for the actor only" do
    assert_equal [ 2, 1 ], [ unread(users(:reader)), unread(users(:author)) ]

    assert as(users(:reader)) { Notes::MarkRead.call(container: @page) }.ok?

    assert_equal [ 1, 1 ], [ unread(users(:reader)), unread(users(:author)) ]
  end

  test "one thread's deliveries are read, which is what opening it does" do
    thread = Notes::Thread.find_by!(container: @page)
    as(users(:two)) { Notes::Start.call(@page, body: "Another, @[#{users(:reader).id}]") }

    assert as(users(:reader)) { Notes::MarkRead.call(thread: thread) }.ok?

    assert_equal [ 2, 0 ], [ unread(users(:reader)), Notes::Delivery.unread.where(user: users(:reader), thread: thread).count ]
  end

  test "all of the actor's deliveries are read, in one statement, and nothing is audited" do
    statements = nil
    assert_no_difference -> { Audit::Event.count } do
      statements = capture_sql { as(users(:reader)) { Notes::MarkRead.call } }
    end

    assert_equal [ 0, 1 ], [ unread(users(:reader)), unread(users(:author)) ]
    assert_equal 1, statements.count { |sql| sql.start_with?("UPDATE") }
  end

  test "a record the actor can't read is refused" do
    stranger = User.create!(email_address: "stranger@example.com", password: "a-long-password-1")

    assert_predicate as(stranger) { Notes::MarkRead.call(container: @page) }, :denied?
  end

  # With a thread or a record named, the read mark follows the one rule of
  # every notes write: the container's lock first, and a record in the trash
  # is gone. "Mark all read" names no record and takes no lock.
  test "a record in the trash is the ordinary failure, for its threads and for one of them, and nothing is read" do
    thread = Notes::Thread.find_by!(container: @page)
    @page.update!(trashed_at: Time.current)

    [ { container: @page }, { thread: thread } ].each do |target|
      result = as(users(:reader)) { Notes::MarkRead.call(**target) }
      assert_equal [ "This note is gone: it was deleted, or what it was on was." ], result.errors, target.keys.inspect
      assert_not_predicate result, :denied?
    end
    assert_equal 2, unread(users(:reader))
  end

  test "the record's row is locked before a notes row is read or written, for a record and for a thread" do
    thread = Notes::Thread.find_by!(container: @post)

    [ [ { container: @page }, "pages" ], [ { thread: thread }, "posts" ] ].each do |target, table|
      statements = capture_sql { assert as(users(:reader)) { Notes::MarkRead.call(**target) }.ok? }
      lock = statements.index { |sql| sql.include?(%(FROM "#{table}")) && sql.include?("FOR UPDATE") }
      notes = statements.index { |sql| sql.include?(%("note_)) }

      assert lock && notes, statements.join("\n")
      assert_operator lock, :<, notes, table
      assert_equal 1, statements.count { |sql| sql.start_with?(%(UPDATE "note_deliveries")) }
    end
    assert_equal 0, unread(users(:reader))
  end
end
