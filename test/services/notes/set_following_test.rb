require "test_helper"

class Notes::SetFollowingTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing")
    @thread = as(users(:two)) { Notes::Start.call(@page, body: "Is this right?") }.record
  end

  def following?(user) = Notes::Follow.find_by(thread: @thread, user: user)&.following

  test "a reader follows a thread they never wrote in, and is then told of a reply" do
    assert_nil following?(users(:reader))

    assert as(users(:reader)) { Notes::SetFollowing.call(@thread, following: true) }.ok?
    assert following?(users(:reader))

    as(users(:two)) { Notes::Reply.call(@thread, body: "More") }
    assert_equal [ [ users(:reader).id, "reply" ] ], Notes::Delivery.pluck(:user_id, :reason)
  end

  test "an unfollow is remembered, and nothing is audited" do
    assert_no_difference -> { Audit::Event.count } do
      assert as(users(:two)) { Notes::SetFollowing.call(@thread, following: false) }.ok?
    end
    assert_equal false, following?(users(:two))

    as(users(:two)) { Notes::Reply.call(@thread, body: "Writing again") }
    assert_equal false, following?(users(:two))
  end

  test "a stranger can't follow" do
    stranger = User.create!(email_address: "stranger@example.com", password: "a-long-password-1")

    assert_predicate as(stranger) { Notes::SetFollowing.call(@thread, following: true) }, :denied?
    assert_nil following?(stranger)
  end

  test "on a page in the trash a follow is the ordinary failure, and no row is written" do
    @page.update!(trashed_at: Time.current)

    result = as(users(:reader)) { Notes::SetFollowing.call(@thread, following: true) }

    assert_equal [ "This note is gone: it was deleted, or what it was on was." ], result.errors
    assert_not_predicate result, :denied?
    assert_nil following?(users(:reader))
  end

  test "a thread deleted meanwhile is the same failure" do
    stale = Notes::Thread.find(@thread.id)
    @thread.destroy!

    assert_equal [ "This note is gone: it was deleted, or what it was on was." ], as(users(:reader)) { Notes::SetFollowing.call(stale, following: true) }.errors
    assert_equal 0, Notes::Follow.count
  end

  test "the page's row is locked before a notes row is read or written" do
    fresh = Notes::Thread.find(@thread.id)
    statements = capture_sql { assert as(users(:reader)) { Notes::SetFollowing.call(fresh, following: true) }.ok? }
    lock = statements.index { |sql| sql.include?(%(FROM "pages")) && sql.include?("FOR UPDATE") }
    notes = statements.index { |sql| sql.include?(%("note_)) }

    assert lock && notes, statements.join("\n")
    assert_operator lock, :<, notes
    assert statements.any? { |sql| sql.start_with?(%(INSERT INTO "note_follows")) }, statements.join("\n")
  end
end
