require "test_helper"

class Editing::TakeOverTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  A = "tab-aaaaaaaa".freeze
  B = "tab-bbbbbbbb".freeze
  C = "tab-cccccccc".freeze

  setup do
    @page = create_page(title: "Pricing", published: false)
    @block = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "image" }).record
    @olga = users(:one)
    @dana = users(:two)
    @stream = Editing::Signals.record_stream(@page)
    @stamp = @block.reload.updated_at
  end

  def hold_as(user, tab, subject: @block, record: @page, at: Time.current)
    Editing::Reservation.claim(subject:, record:, user:, tab:, now: at)
  end

  def signals = broadcasts(@stream).map { |payload| ActiveSupport::JSON.decode(payload) }.select { |signal| signal["kind"] == "holder" }

  def take(user = @dana, tab = B, subject: @block, record: @page, hand_over: false)
    service = Editing::TakeOver.new(subject, record:, tab:, hand_over:, actor: user)
    result = as(user) { service.call }
    [ service, result ]
  end

  def row = Editing::Reservation.sole
  def events(action = "block.taken_over") = Audit::Event.where(action:)

  test "asking writes the request and tells the holder's tab; nothing is audited and nobody's row has moved" do
    hold_as(@olga, A)

    service = nil
    assert_no_difference -> { Audit::Event.count } do
      assert as(@dana) { (service = Editing::TakeOver.new(@block, record: @page, tab: B)).call }.ok?
    end

    assert_equal :requested, service.outcome
    assert_equal [ @olga.id, A, @dana.id, B ], row.values_at(:user_id, :tab, :requested_by_id, :requested_tab)
    assert_equal [ { "kind" => "holder", "content_block_id" => @block.id, "reason" => "requested" } ], signals
  end

  test "the hand-over passes the row, audits once on the block with both ids and no text, and tells everyone" do
    hold_as(@olga, A)
    take

    service = nil
    assert_difference -> { events.count }, 1 do
      assert as(@olga) { (service = Editing::TakeOver.new(@block, record: @page, tab: A, hand_over: true)).call }.ok?
    end

    event = events.last
    assert_equal :handed, service.outcome
    assert_equal [ @dana.id, B ], row.values_at(:user_id, :tab)
    assert_nil row.requested_by_id
    assert_equal({ "from_user_id" => @olga.id, "to_user_id" => @dana.id, "answered" => true }, event.metadata)
    assert_equal [ "ContentBlock", @block.id, nil, @olga.id ], [ event.subject_type, event.subject_id, event.snapshot, event.user_id ]
    assert_equal "taken", signals.last["reason"]
    assert_equal @stamp, @block.reload.updated_at, "a take-over wrote the block"
  end

  test "asked again before the pass-over time it is still a request, with its first time kept; at the pass-over time the row is the requester's, not answered" do
    hold_as(@olga, A)
    first = Time.current.change(usec: 0)
    travel_to(first) { take }
    requested_at = row.requested_at

    travel_to(first + Editing::PASS_OVER - 1) do
      service, = take
      assert_equal :requested, service.outcome
    end
    assert_equal requested_at, row.requested_at
    assert_equal 0, events.count

    travel_to(first + Editing::PASS_OVER) do
      service, result = take
      assert result.ok?
      assert_equal :taken, service.outcome
    end
    assert_equal [ @dana.id, B ], row.values_at(:user_id, :tab)
    assert_equal({ "from_user_id" => @olga.id, "to_user_id" => @dana.id, "answered" => false }, events.sole.metadata)
    assert_equal "taken", signals.last["reason"]
  end

  test "an expired hold is simply claimed: no request, no event" do
    hold_as(@olga, A, at: 5.minutes.ago)

    service, = take

    assert_equal :claimed, service.outcome
    assert_equal [ @dana.id, B ], row.values_at(:user_id, :tab)
    assert_equal 0, Audit::Event.where(action: "block.taken_over").count
    assert_equal "claimed", signals.last["reason"]
  end

  test "an expired hold with a due request is claimed, not passed over" do
    hold_as(@olga, A, at: 5.minutes.ago)
    Editing::Reservation.update_all(requested_by_id: @dana.id, requested_tab: B, requested_at: 4.minutes.ago) # version: none (a test builds a stale request)

    service, = take

    assert_equal :claimed, service.outcome
    assert_equal 0, events.count
  end

  test "a subject nobody holds is claimed" do
    service, = take

    assert_equal :claimed, service.outcome
    assert_equal [ @dana.id, B ], row.values_at(:user_id, :tab)
    assert_equal [ "claimed" ], signals.map { |signal| signal["reason"] }
    assert_equal 0, events.count
  end

  test "asking for what one's own tab holds renews it and sends nothing" do
    hold_as(@dana, B)

    service, = take

    assert_equal :claimed, service.outcome
    assert_empty signals
  end

  test "taking over from one's own other tab works the same, and is audited with the same person on both sides" do
    hold_as(@dana, A)
    take(@dana, B)
    service, = take(@dana, A, hand_over: true)

    assert_equal :handed, service.outcome
    assert_equal [ @dana.id, B ], row.values_at(:user_id, :tab)
    assert_equal({ "from_user_id" => @dana.id, "to_user_id" => @dana.id, "answered" => true }, events.sole.metadata)
  end

  test "anyone who may save it may take it back: the new holder's other tab and the old holder in turn" do
    hold_as(@olga, A)
    take
    take(@olga, A, hand_over: true)

    service, = take(@olga, C)
    assert_equal :requested, service.outcome
    service, = take(@dana, B, hand_over: true)
    assert_equal :handed, service.outcome
    assert_equal [ @olga.id, C ], row.values_at(:user_id, :tab)
    assert_equal 2, events.count
  end

  test "a hand-over from a tab that does not hold it, or with nobody asking, does nothing and audits nothing" do
    hold_as(@olga, A)

    service, result = take(@olga, A, hand_over: true)
    assert_equal :nothing, service.outcome
    assert result.ok?

    take
    service, = take(@olga, C, hand_over: true)
    assert_equal :nothing, service.outcome
    service, = take(@dana, B, hand_over: true)
    assert_equal :nothing, service.outcome

    assert_equal [ @olga.id, A, @dana.id ], row.values_at(:user_id, :tab, :requested_by_id)
    assert_equal 0, events.count
    Editing::Reservation.release(subject: @block, user: @olga, tab: A)
    service, = take(@olga, A, hand_over: true)
    assert_equal :nothing, service.outcome
  end

  test "a hand-over after the hold expired does nothing: the requester claims" do
    hold_as(@olga, A, at: 3.minutes.ago)
    Editing::Reservation.update_all(requested_by_id: @dana.id, requested_tab: B, requested_at: 2.minutes.ago) # version: none (a test builds a stale request)

    service, = take(@olga, A, hand_over: true)

    assert_equal :nothing, service.outcome
    assert_equal 0, events.count
  end

  test "two requesters: the second is pending and changes nothing, the first's pass-over succeeds" do
    hold_as(@olga, A)
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "pages.edit", scope: {})
    third = users(:editor_branch)
    first = Time.current.change(usec: 0)
    travel_to(first) { take }

    travel_to(first + 1) do
      service, result = take(third, C)
      assert result.ok?
      assert_equal :pending, service.outcome
    end
    assert_equal [ @dana.id, B ], row.values_at(:requested_by_id, :requested_tab)
    assert_equal [ "requested" ], signals.map { |signal| signal["reason"] }, "a pending answer sends nothing"
    assert_equal 0, events.count

    travel_to(first + Editing::PASS_OVER) do
      service, = take
      assert_equal :taken, service.outcome
    end
  end

  test "a request whose requester never came back is replaced after twice the pass-over time, and the old requester's own late call starts afresh" do
    hold_as(@olga, A, at: Time.current + 2 * Editing::PASS_OVER)
    first = Time.current.change(usec: 0)
    Editing::Reservation.request(subject: @block, by: @dana, tab: B, now: first)
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "pages.edit", scope: {})
    third = users(:editor_branch)

    travel_to(first + 2 * Editing::PASS_OVER + 1) do
      service, = take(third, C)
      assert_equal :requested, service.outcome
    end
    assert_equal [ third.id, C ], row.values_at(:requested_by_id, :requested_tab)

    # Dana's own call now is a stranger's to the row: her request was replaced, so the third is first and she is pending.
    travel_to(first + 2 * Editing::PASS_OVER + 2) do
      service, = take
      assert_equal :pending, service.outcome
    end
  end

  test "the holder releases while a request is pending: the requester then simply claims" do
    hold_as(@olga, A)
    take
    Editing::Reservation.release(subject: @block, user: @olga, tab: A)

    service, = take

    assert_equal :claimed, service.outcome
    assert_equal [ @dana.id, B ], row.values_at(:user_id, :tab)
    assert_equal 0, events.count
  end

  test "without the right it is denied, with one access.denied, and the row is untouched" do
    hold_as(@olga, A)
    before = row.attributes

    service, result = take(users(:reader), C)

    assert_predicate result, :denied?
    assert_nil service.outcome
    assert_equal before, row.attributes
    assert_equal [ "access.denied" ], Audit::Event.where(user_id: users(:reader).id).pluck(:action)
  end

  test "on a published page, edit without publish is denied too" do
    published = create_page(title: "Live", published: true)
    block = ContentBlocks::Save.call(ContentBlock.new(owner: published), attributes: { block_type: "rich_text" }).record
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "pages.edit", scope: {})
    editor = users(:editor_branch)
    hold_as(@olga, A, subject: block, record: published)

    _, result = take(editor, C, subject: block, record: published)

    assert_predicate result, :denied?
    assert_nil Editing::Reservation.sole.requested_by_id
  end

  test "a holder who has lost the right cannot hand over, and the requester gets the block after the pass-over time" do
    grant = AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "pages.edit", scope: {})
    holder = users(:editor_branch)
    hold_as(holder, A)
    first = Time.current.change(usec: 0)
    travel_to(first) { take }
    grant.destroy!

    service, result = take(holder, A, hand_over: true)

    assert_predicate result, :denied?
    assert_nil service.outcome
    assert_equal [ holder.id, A ], row.values_at(:user_id, :tab), "the row is still the holder's"
    assert_equal 0, events.count

    travel_to(first + Editing::PASS_OVER + 1) do
      service, = take
      assert_equal :taken, service.outcome
    end
    assert_equal [ @dana.id, B ], row.values_at(:user_id, :tab)
  end

  test "no tab id, or nobody signed in, is a failure and changes nothing" do
    hold_as(@olga, A)

    _, result = take(@dana, nil)
    assert_not result.ok?
    assert_not result.denied?
    assert_nil row.requested_by_id
  end

  test "the event names nobody and nothing: its metadata is two ids and a flag" do
    hold_as(@olga, A)
    take
    take(@olga, A, hand_over: true)

    event = events.sole
    assert_equal %w[answered from_user_id to_user_id], event.metadata.keys.sort
    assert_nil event.snapshot
    assert_equal({}, event.field_changes.to_h)
    assert_equal 1, event.occurrences
  end

  test "a page's settings and a post are taken over with their own event" do
    post = create_post(title: "News", published: false)
    hold_as(@olga, A, subject: @page)
    hold_as(@olga, A, subject: post, record: post)

    take(@dana, B, subject: @page)
    take(@olga, A, subject: @page, hand_over: true)
    take(@dana, B, subject: post, record: post)
    take(@olga, A, subject: post, record: post, hand_over: true)

    assert_equal [ "Page", @page.id ], events("page.taken_over").pick(:subject_type, :subject_id)
    assert_equal [ "Post", post.id ], events("post.taken_over").pick(:subject_type, :subject_id)
  end

  test "a take-over is not a change: the dashboard's 'by', 'Changed by …' and 'Updated by …' skip it, and nothing a stale check reads moves" do
    travel 1.minute
    saved = as(@olga) { ContentBlocks::Save.call(@block, translations: { "en" => { caption: "x" } }) }
    assert saved.ok?, saved.errors.inspect
    page_stamp = @page.reload.updated_at
    settings_stamp = @page.settings_changed_at
    block_stamp = @block.reload.updated_at
    travel 1.second
    since = Time.current
    hold_as(@dana, A)
    take(@olga, B)
    take(@dana, A, hand_over: true)
    assert_equal 1, events.count

    assert_equal [ page_stamp, settings_stamp, block_stamp ], [ @page.reload.updated_at, @page.settings_changed_at, @block.reload.updated_at ]
    change = Audit::ChangeSince.for(@block, since:, viewer: @dana)
    assert_nil change, "Changed by: named a take-over"
    assert_equal @olga.id, Editing::LastChange.for(@block, viewer: @dana)&.user&.id, "Updated by: named a take-over"
    assert_includes Dashboard::Feed::NOT_A_CHANGE, "block.taken_over"
    assert_includes Dashboard::Feed.new(actor: @olga).drafts, @page, "the take-over took the page off its last editor's drafts"
    assert_not_includes Dashboard::Feed.new(actor: @dana).drafts, @page, "the take-over put the page on its handing-over actor's drafts"
  end
  test "this tab's own request older than twice the pass-over time is still passed over" do
    hold_as(@olga, A)
    first = Time.current.change(usec: 0)
    travel_to(first) { take }

    travel_to(first + 3 * Editing::PASS_OVER) do
      hold_as(@olga, A) # the holder keeps typing: the row is live
      service, = take
      assert_equal :taken, service.outcome
    end
    assert_equal [ @dana.id, B ], row.values_at(:user_id, :tab)
    assert_equal 1, events.count
  end

  test "a hand-over after the requester's user was deleted does nothing" do
    requester = User.create!(email_address: "gone@example.com", password: "a-long-password-1")
    hold_as(@olga, A)
    Editing::Reservation.update_all(requested_by_id: requester.id, requested_tab: C, requested_at: Time.current) # version: none (a test builds a request)
    requester.destroy!

    service, = take(@olga, A, hand_over: true)

    assert_equal :nothing, service.outcome
    assert_equal [ @olga.id, A ], row.values_at(:user_id, :tab)
    assert_equal 0, events.count
  end

  test "a published post needs publish as well as edit to be taken over or handed over" do
    post = create_post(title: "Live", published: true)
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "posts.edit", scope: {})
    editor = users(:editor_branch)
    hold_as(@olga, A, subject: post, record: post)

    _, result = take(editor, C, subject: post, record: post)
    assert_predicate result, :denied?
    _, result = take(editor, C, subject: post, record: post, hand_over: true)
    assert_predicate result, :denied?

    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "posts.publish", scope: {})
    service, result = take(editor, C, subject: post, record: post)
    assert result.ok?
    assert_equal :requested, service.outcome
  end
end

# Two connections need rows the other can see, so this class runs outside the
# test transaction, on a subject that does not exist (a reservation has no
# foreign key to it) and with a service whose events are collected instead of
# written (the audit log is append-only: a committed event could not be
# cleaned up). `behind` is the reservation race test's: the first call holds
# its transaction open until Postgres says the second is waiting behind it.
class Editing::TakeOverRaceTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  A = "tab-aaaaaaaa".freeze
  B = "tab-bbbbbbbb".freeze
  C = "tab-cccccccc".freeze
  ID = 9_000_000_003

  class Recording < Editing::TakeOver
    EVENTS = Queue.new

    def record_event(action, subject: nil, metadata: {}, **) = EVENTS << [ action, metadata ]
  end

  setup do
    @olga = users(:one)
    @dana = users(:two)
    @subject = ContentBlock.new(id: ID)
    @record = Page.new(id: ID)
    clean
  end

  teardown { clean }

  def clean
    Editing::Reservation.where(subject_id: ID).delete_all # version: none (a test's own rows)
    Recording::EVENTS.clear
  end

  def events = Array.new(Recording::EVENTS.size) { Recording::EVENTS.pop }

  def row = Editing::Reservation.find_by!(subject_id: ID)

  def hold(user, tab, at: 20.seconds.ago) = Editing::Reservation.claim(subject: @subject, record: @record, user:, tab:, now: at)

  def ask(user, tab, at: 16.seconds.ago) = Editing::Reservation.request(subject: @subject, by: user, tab:, now: at)

  # The service as `user` from `tab`; the answer is its outcome.
  def call(user, tab, hand_over: false)
    -> {
      service = Recording.new(@subject, record: @record, tab:, hand_over:, actor: user)
      raise service_failure(service) unless service.call.ok?

      service.outcome
    }
  end

  def service_failure(service) = "the call failed: #{service.outcome.inspect}"

  def behind(first, second)
    thread = nil
    first_answer = Editing::Reservation.transaction do
      answer = first.call
      thread = Thread.new { ActiveRecord::Base.connection_pool.with_connection { second.call } }
      await_blocked
      answer
    end
    [ first_answer, thread.value ]
  ensure
    thread&.join
  end

  BLOCKED = "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND wait_event_type = 'Lock' AND query LIKE '%edit_reservations%'".freeze

  def blocked? = Thread.new { ActiveRecord::Base.connection_pool.with_connection { ActiveRecord::Base.connection.select_value(BLOCKED).to_i.positive? } }.value

  def await_blocked
    200.times do
      return if blocked?

      sleep 0.025 # sleep: polling Postgres for the second statement to be waiting on the first's lock
    end
    flunk "the second statement never blocked behind the first"
  end

  test "take-over of a free subject and a take-over from another tab: the first claims, the second asks it, nothing is audited" do
    first, second = behind(call(@olga, A), call(@dana, B))

    assert_equal %i[claimed requested], [ first, second ]
    assert_equal [ @olga.id, A, @dana.id, B ], row.values_at(:user_id, :tab, :requested_by_id, :requested_tab)
    assert_empty events
  end

  test "a pass-over and the same pass-over again: taken, then claimed, and one event" do
    hold(@olga, A)
    ask(@dana, B)

    first, second = behind(call(@dana, B), call(@dana, B))

    assert_equal %i[taken claimed], [ first, second ]
    assert_equal [ @dana.id, B ], row.values_at(:user_id, :tab)
    assert_equal [ [ "block.taken_over", { "from_user_id" => @olga.id, "to_user_id" => @dana.id, "answered" => false } ] ], events
  end

  test "a hand-over and then a pass-over: handed, then claimed, and one event marked answered" do
    hold(@olga, A)
    ask(@dana, B)

    first, second = behind(call(@olga, A, hand_over: true), call(@dana, B))

    assert_equal %i[handed claimed], [ first, second ]
    assert_equal [ [ "block.taken_over", { "from_user_id" => @olga.id, "to_user_id" => @dana.id, "answered" => true } ] ], events
  end

  test "a pass-over and then a hand-over: taken, then nothing, and one event marked not answered" do
    hold(@olga, A)
    ask(@dana, B)

    first, second = behind(call(@dana, B), call(@olga, A, hand_over: true))

    assert_equal %i[taken nothing], [ first, second ]
    assert_equal [ @dana.id, B ], row.values_at(:user_id, :tab)
    assert_equal [ [ "block.taken_over", { "from_user_id" => @olga.id, "to_user_id" => @dana.id, "answered" => false } ] ], events
  end

  test "the row is read under its lock: a hand-over goes to, and is audited for, the requester who replaced a stale one while it waited" do
    hold(@olga, A)
    ask(users(:reader), C, at: 16.seconds.ago) # older than twice the pass-over time: anyone may replace it

    first, second = behind(call(@dana, B), call(@olga, A, hand_over: true))

    assert_equal %i[requested handed], [ first, second ]
    assert_equal [ @dana.id, B ], row.values_at(:user_id, :tab)
    assert_equal [ [ "block.taken_over", { "from_user_id" => @olga.id, "to_user_id" => @dana.id, "answered" => true } ] ], events
  end
end
