require "test_helper"

# `Publishing::State`: the one object that says which of six things a page or
# post is and what may be done to it (drafts plan, task 6, addition 1). Three
# facts, nothing stored: the time (`published_at`), a copy pending, the mark.
class Publishing::StateTest < ActiveSupport::TestCase
  # [time, pending copy, mark] => [state, changes?, actions]. EVERY combination
  # of the three facts (3 x 2 x 2), the impossible ones included: a mark or
  # a pending copy on a draft is answered as the draft it is.
  TABLE = {
    [ :none, false, false ] => [ :draft, false, %i[publish schedule] ],
    [ :none, false, true ] => [ :draft, false, %i[publish schedule] ],
    [ :none, true, false ] => [ :draft, false, %i[publish schedule] ],
    [ :none, true, true ] => [ :draft, false, %i[publish schedule] ],
    [ :future, false, false ] => [ :scheduled, false, %i[publish schedule unpublish] ],
    [ :future, false, true ] => [ :scheduled, true, %i[publish schedule publish_changes discard_changes unpublish] ],
    [ :future, true, false ] => [ :scheduled, false, %i[publish schedule unpublish] ],
    [ :future, true, true ] => [ :scheduled, true, %i[publish schedule publish_changes discard_changes unpublish] ],
    [ :past, false, false ] => [ :live, false, %i[unpublish] ],
    [ :past, false, true ] => [ :live_with_changes, true, %i[publish_changes discard_changes unpublish] ],
    [ :past, true, false ] => [ :live_change_scheduled, false, %i[publish_changes cancel_scheduled_change discard_changes unpublish] ],
    [ :past, true, true ] => [ :live_change_scheduled, true, %i[publish_changes cancel_scheduled_change discard_changes unpublish] ]
  }.freeze

  def record_with(time, pending, mark, kind: :page)
    @count = (@count || 0) + 1
    record = kind == :page ? create_page(title: "State #{@count}") : create_post(title: "State #{@count}")
    Publishing::Version.take!(record, live_at: 2.days.from_now) if pending
    attributes = { published_at: { none: nil, future: 3.days.from_now, past: 1.day.ago }.fetch(time), unpublished_changes_at: (Time.current if mark) }
    record.update_columns(**attributes) # version: none (a test sets the facts a state is derived from) # changes: none (a test sets the facts a state is derived from)
    record.reload
  end

  test "every combination of the time, a pending copy and the mark is exactly one state, with its actions" do
    assert_equal 12, TABLE.size
    TABLE.each do |(time, pending, mark), (state, changes, actions)|
      %i[page post].each do |kind|
        result = Publishing::State.of(record_with(time, pending, mark, kind: kind))

        assert_equal state, result.state, "#{kind} #{time} pending=#{pending} mark=#{mark}"
        assert_includes Publishing::State::STATES, result.state
        assert_equal changes, result.changes?, "#{kind} #{time} pending=#{pending} mark=#{mark}"
        assert_equal actions, result.actions, "#{kind} #{time} pending=#{pending} mark=#{mark}"
        assert_empty result.actions - Publishing::State::ACTIONS
      end
    end
  end

  test "a copy pending says when it comes into force, and only for a record that has a time" do
    live = record_with(:past, true, false)
    assert_equal Publishing.pending(live).live_at, Publishing::State.of(live).pending_at
    assert_nil Publishing::State.of(record_with(:past, false, false)).pending_at
    assert_nil Publishing::State.of(record_with(:none, true, false)).pending_at, "a draft keeps copies and uses none"
  end

  test "the state is judged at the time asked: a record scheduled for tomorrow is live the day after" do
    scheduled = record_with(:future, false, false)

    assert_equal :scheduled, Publishing::State.of(scheduled).state
    assert_equal :live, Publishing::State.of(scheduled, now: 4.days.from_now).state
  end

  test "the cheap question, whether the rows moved on, reads the record and asks the database nothing" do
    live = record_with(:past, false, true)
    queries = capture_sql { assert Publishing::State.of(live).changes? }

    assert_empty queries
  end

  test "Publishable#unpublished_changes? and its scope agree with the state, for every combination" do
    TABLE.each do |(time, pending, mark), (_state, changes, _actions)|
      page = record_with(time, pending, mark)

      assert_equal changes, page.unpublished_changes?, "#{time} #{pending} #{mark}"
      assert_equal changes, Page.with_unpublished_changes.exists?(page.id), "#{time} #{pending} #{mark}: the scope"
      post = record_with(time, pending, mark, kind: :post)
      assert_equal changes, Post.with_unpublished_changes.exists?(post.id), "#{time} #{pending} #{mark}: the scope, for a post"
    end
  end

  test "Publishable#status and the state's status are one answer, for every combination, and the booleans follow" do
    TABLE.each_key do |time, pending, mark|
      record = record_with(time, pending, mark)
      state = Publishing::State.of(record)

      assert_equal state.status, record.status, "#{time} #{pending} #{mark}"
      assert_equal state.live?, record.live?
      assert_equal({ none: "draft", future: "scheduled", past: "live" }.fetch(time), state.status)
    end
  end

  test "a copy pending on a live record offers every way out of it, with or without edits since" do
    [ false, true ].each do |mark|
      actions = Publishing::State.of(record_with(:past, true, mark)).actions

      assert_includes actions, :publish_changes
      assert_includes actions, :cancel_scheduled_change
      assert_includes actions, :discard_changes
    end
  end
end
