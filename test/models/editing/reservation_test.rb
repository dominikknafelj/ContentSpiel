require "test_helper"

class Editing::ReservationTest < ActiveSupport::TestCase
  A = "tab-aaaaaaaa".freeze
  B = "tab-bbbbbbbb".freeze

  setup do
    @page = create_page(title: "Pricing", published: false)
    @block = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" }).record
    @olga = users(:one)
    @dana = users(:two)
    @now = Time.current.change(usec: 0)
  end

  def claim(user, tab, at: @now, subject: @block) = Editing::Reservation.claim(subject:, record: @page, user:, tab:, now: at)

  test "the first claim takes, the same tab's next renews, and anyone else is refused: another person, and the same person's other tab" do
    assert_equal :taken, claim(@olga, A)
    assert_equal :renewed, claim(@olga, A, at: @now + 30.seconds)
    assert_equal :refused, claim(@dana, B, at: @now + 40.seconds)
    assert_equal :refused, claim(@olga, B, at: @now + 40.seconds)

    row = Editing::Reservation.sole
    assert_equal [ "ContentBlock", @block.id, "Page", @page.id, @olga.id, A ], row.values_at(:subject_type, :subject_id, :record_type, :record_id, :user_id, :tab)
    assert_equal @now + 30.seconds, row.changed_at
  end

  test "a row is live until HOLD after its last change: one instant before it is refused, at it the row is taken" do
    claim(@olga, A)

    assert_equal :refused, claim(@dana, B, at: @now + Editing::HOLD - 0.001)
    assert_equal @olga.id, Editing::Reservation.holder_of(@block, now: @now + Editing::HOLD - 0.001).user_id
    assert_nil Editing::Reservation.holder_of(@block, now: @now + Editing::HOLD)
    assert_equal :taken, claim(@dana, B, at: @now + Editing::HOLD)
    assert_equal [ @dana.id, B ], Editing::Reservation.sole.values_at(:user_id, :tab)
  end

  test "the holder's own claim after its row expired takes it again, and says so" do
    claim(@olga, A)
    assert_equal :taken, claim(@olga, A, at: @now + Editing::HOLD + 1)
  end

  test "a page's settings and a post are subjects too, each its own" do
    post = create_post(title: "News", published: false)
    assert_equal :taken, claim(@olga, A, subject: @page)
    assert_equal :taken, Editing::Reservation.claim(subject: post, record: post, user: @dana, tab: B, now: @now)
    assert_equal :taken, claim(@dana, B)
    assert_equal 3, Editing::Reservation.count
  end

  test "release deletes only the row of that tab" do
    claim(@olga, A)

    assert_not Editing::Reservation.release(subject: @block, user: @dana, tab: B)
    assert_not Editing::Reservation.release(subject: @block, user: @olga, tab: B)
    assert Editing::Reservation.release(subject: @block, user: @olga, tab: A)
    assert_equal 0, Editing::Reservation.count
  end

  test "a request is written on another tab's live row, keeps its time when asked again, and is none on one's own or an expired row" do
    claim(@olga, A)

    assert_equal :none, Editing::Reservation.request(subject: @block, by: @olga, tab: A, now: @now)
    assert_equal :requested, Editing::Reservation.request(subject: @block, by: @dana, tab: B, now: @now + 1)
    assert_equal :requested, Editing::Reservation.request(subject: @block, by: @dana, tab: B, now: @now + 3)
    assert_equal [ @dana.id, B, @now + 1 ], Editing::Reservation.sole.values_at(:requested_by_id, :requested_tab, :requested_at)
    assert_equal :none, Editing::Reservation.request(subject: @block, by: @dana, tab: B, now: @now + Editing::HOLD + 5)
    assert_equal :none, Editing::Reservation.request(subject: ContentBlock.new(id: 9_000_000_002), by: @dana, tab: B, now: @now)
  end

  test "the first requester keeps the request: another asking while it stands is pending and changes nothing" do
    claim(@olga, A)
    reader = users(:reader)
    assert_equal :requested, Editing::Reservation.request(subject: @block, by: @dana, tab: B, now: @now)

    assert_equal :pending, Editing::Reservation.request(subject: @block, by: reader, tab: "tab-cccccccc", now: @now + 1)
    assert_equal :pending, Editing::Reservation.request(subject: @block, by: reader, tab: "tab-cccccccc", now: @now + 2 * Editing::PASS_OVER - 0.001)
    assert_equal [ @dana.id, B, @now ], Editing::Reservation.sole.values_at(:requested_by_id, :requested_tab, :requested_at)
    assert Editing::Reservation.pass_over(subject: @block, by: @dana, tab: B, now: @now + Editing::PASS_OVER), "the first requester can still pass over"
  end

  test "a request older than twice PASS_OVER that nobody passed over may be replaced, by another tab or starts afresh by the same tab" do
    claim(@olga, A)
    reader = users(:reader)
    Editing::Reservation.request(subject: @block, by: @dana, tab: B, now: @now)
    late = @now + 2 * Editing::PASS_OVER

    assert_equal :requested, Editing::Reservation.request(subject: @block, by: reader, tab: "tab-cccccccc", now: late)
    assert_equal [ reader.id, "tab-cccccccc", late ], Editing::Reservation.sole.values_at(:requested_by_id, :requested_tab, :requested_at)

    # The same tab: kept one instant before the age, afresh at it.
    Editing::Reservation.request(subject: @block, by: reader, tab: "tab-cccccccc", now: late + 2 * Editing::PASS_OVER - 0.001)
    assert_equal late, Editing::Reservation.sole.requested_at
    assert_equal :requested, Editing::Reservation.request(subject: @block, by: reader, tab: "tab-cccccccc", now: late + 2 * Editing::PASS_OVER)
    assert_equal late + 2 * Editing::PASS_OVER, Editing::Reservation.sole.requested_at
  end

  test "the holder's renewal keeps a pending request; a claim of the expired row drops it" do
    claim(@olga, A)
    Editing::Reservation.request(subject: @block, by: @dana, tab: B, now: @now + 1)

    claim(@olga, A, at: @now + 2)
    assert_equal @dana.id, Editing::Reservation.sole.requested_by_id

    claim(users(:reader), "tab-cccccccc", at: @now + Editing::HOLD + 10)
    assert_nil Editing::Reservation.sole.requested_by_id
  end

  test "hand-over passes the row to the requester, once, and only from the holder's tab" do
    claim(@olga, A)
    assert_not Editing::Reservation.hand_over(subject: @block, user: @olga, tab: A, now: @now), "nobody asked"
    Editing::Reservation.request(subject: @block, by: @dana, tab: B, now: @now + 1)

    assert_not Editing::Reservation.hand_over(subject: @block, user: @olga, tab: B, now: @now + 2)
    assert Editing::Reservation.hand_over(subject: @block, user: @olga, tab: A, now: @now + 2)
    assert_equal [ @dana.id, B, @now + 2, nil, nil, nil ], Editing::Reservation.sole.values_at(:user_id, :tab, :changed_at, :requested_by_id, :requested_tab, :requested_at)
    assert_not Editing::Reservation.hand_over(subject: @block, user: @olga, tab: A, now: @now + 3)
  end

  test "pass-over gives the row to the requester once the request is PASS_OVER old, not a moment before, and to nobody else" do
    claim(@olga, A)
    Editing::Reservation.request(subject: @block, by: @dana, tab: B, now: @now)

    assert_not Editing::Reservation.pass_over(subject: @block, by: @dana, tab: B, now: @now + Editing::PASS_OVER - 0.001)
    assert_not Editing::Reservation.pass_over(subject: @block, by: users(:reader), tab: B, now: @now + Editing::PASS_OVER)
    assert Editing::Reservation.pass_over(subject: @block, by: @dana, tab: B, now: @now + Editing::PASS_OVER)
    assert_equal [ @dana.id, B ], Editing::Reservation.sole.values_at(:user_id, :tab)
  end

  test "every statement is one statement, takes no lock and writes nothing but its own row" do
    version = PublicSite.current_content_version
    stamps = [ @page.reload.updated_at, @page.settings_changed_at, @block.reload.updated_at ]
    events = Audit::Event.count

    statements = capture_sql do
      claim(@olga, A)
      claim(@olga, A, at: @now + 1)
      Editing::Reservation.request(subject: @block, by: @dana, tab: B, now: @now + 2)
      Editing::Reservation.hand_over(subject: @block, user: @olga, tab: A, now: @now + 3)
      Editing::Reservation.pass_over(subject: @block, by: @olga, tab: A, now: @now + 4)
      Editing::Reservation.release(subject: @block, user: @dana, tab: B)
    end

    assert_equal 6, statements.size
    assert statements.all? { |sql| sql.include?("edit_reservations") }
    assert statements.none? { |sql| sql.match?(/FOR UPDATE|\bpages\b|\bcontent_blocks\b|\bposts\b/i) }
    assert_equal stamps, [ @page.reload.updated_at, @page.settings_changed_at, @block.reload.updated_at ]
    assert_equal version, PublicSite.current_content_version
    assert_equal events, Audit::Event.count
  end

  test "a request whose requester is deleted is gone: nothing pending, nothing stale after the holder's next renewal" do
    claim(@olga, A)
    leaver = User.create!(email_address: "leaver@example.com", password: "a-long-password-1")
    assert_equal :requested, Editing::Reservation.request(subject: @block, by: leaver, tab: "tab-cccccccc", now: @now + 1)
    assert Editing::Reservation.sole.requested?

    leaver.destroy!
    row = Editing::Reservation.sole
    assert_not row.requested?
    assert_not Editing::Reservation.hand_over(subject: @block, user: @olga, tab: A, now: @now + 2), "nobody is asking any more"

    claim(@olga, A, at: @now + 3)
    assert_equal [ nil, nil, nil ], Editing::Reservation.sole.values_at(:requested_by_id, :requested_tab, :requested_at)
  end

  test "deleting the holder deletes the row" do
    holder = User.create!(email_address: "holder@example.com", password: "a-long-password-1")
    claim(holder, A)
    holder.destroy!
    assert_equal 0, Editing::Reservation.count
  end
end

# Two connections at once need rows the other connection can see, so this
# class runs outside the test transaction and names subjects that do not
# exist (a reservation has no foreign key to its subject).
class Editing::ReservationRaceTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  A = "tab-aaaaaaaa".freeze
  B = "tab-bbbbbbbb".freeze
  ID = 9_000_000_001

  setup do
    @olga = users(:one)
    @dana = users(:two)
    @subject = ContentBlock.new(id: ID)
    @record = Page.new(id: ID)
    clean
  end

  teardown { clean }

  # By subject id, so a test that raised cannot leave a committed row behind.
  def clean = Editing::Reservation.where(subject_id: ID).delete_all # version: none (a test's own rows)

  def claim(user, tab, **) = Editing::Reservation.claim(subject: @subject, record: @record, user:, tab:, **)

  def row = Editing::Reservation.find_by!(subject_id: ID)

  # Real threads, each on its own connection, let go together. Every thread is
  # joined, so none outlives the test, whatever raised.
  def at_once(callers)
    gate = Queue.new
    threads = callers.map do |caller|
      Thread.new { ActiveRecord::Base.connection_pool.with_connection { gate.pop; caller.call } }
    end
    callers.size.times { gate << :go }
    threads.map { |thread| thread.join.value }
  ensure
    threads&.each(&:join)
  end

  # The order forced, not hoped for: `first` runs in a transaction that stays
  # open; `second` is started on another connection and waited for until
  # Postgres says it is blocked behind the first; then the first commits and
  # the second goes on. Returns both answers.
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

  # Asked from a connection of its own: inside the open transaction Postgres
  # would answer from the snapshot of its first look.
  def blocked? = Thread.new { ActiveRecord::Base.connection_pool.with_connection { ActiveRecord::Base.connection.select_value(BLOCKED).to_i.positive? } }.value

  def await_blocked
    200.times do
      return if blocked?

      sleep 0.025 # sleep: polling Postgres for the second statement to be waiting on the first's lock
    end
    flunk "the second statement never blocked behind the first"
  end

  test "two tabs claiming a free subject at once: one takes it, the other is refused, and there is one row" do
    20.times do
      clean
      results = at_once([ [ @olga, A ], [ @dana, B ] ].map { |user, tab| -> { claim(user, tab) } })

      assert_equal %i[refused taken], results.sort
      assert_equal 1, Editing::Reservation.where(subject_id: ID).count
    end
  end

  test "a holder renewing a live row and a stranger claiming it: the holder renews and the stranger is refused" do
    20.times do
      clean
      claim(@olga, A, now: Time.current - Editing::HOLD + 30.seconds)
      results = at_once([ -> { claim(@olga, A) }, -> { claim(@dana, B) } ])

      assert_equal %i[refused renewed], results.sort
      assert_equal [ @olga.id, A ], row.values_at(:user_id, :tab)
    end
  end

  test "an expired row claimed by its holder and by a stranger at once: exactly one holds afterwards" do
    20.times do
      clean
      claim(@olga, A, now: Time.current - Editing::HOLD - 1)
      results = at_once([ -> { claim(@olga, A) }, -> { claim(@dana, B) } ])

      assert_equal 1, results.count(:taken), results.inspect
      assert_equal 1, results.count(:refused), results.inspect
      assert_equal 1, Editing::Reservation.where(subject_id: ID).count
    end
  end

  test "a claim that inserts is taken, even from the tab whose own release it raced: the release commits between its snapshot and its insert" do
    claim(@olga, A)

    released, claimed = behind(-> { Editing::Reservation.release(subject: @subject, user: @olga, tab: A) }, -> { claim(@olga, A) })

    assert released
    assert_equal :taken, claimed
    assert_equal [ @olga.id, A ], row.values_at(:user_id, :tab)
  end

  test "a hand-over and a pass-over of one request: exactly one transfers" do
    claim(@olga, A)
    now = Time.current
    Editing::Reservation.request(subject: @subject, by: @dana, tab: B, now: now - 10.seconds)

    handed, passed = behind(
      -> { Editing::Reservation.hand_over(subject: @subject, user: @olga, tab: A, now:) },
      -> { Editing::Reservation.pass_over(subject: @subject, by: @dana, tab: B, now:) }
    )

    assert_equal [ true, false ], [ handed, passed ]
    assert_equal [ @dana.id, B ], row.values_at(:user_id, :tab)
  end

  test "a request and the holder's renewal at once: the request survives" do
    claim(@olga, A)

    requested, renewed = behind(
      -> { Editing::Reservation.request(subject: @subject, by: @dana, tab: B) },
      -> { claim(@olga, A) }
    )

    assert_equal :requested, requested
    assert_equal :renewed, renewed
    assert_equal [ @olga.id, A, @dana.id, B ], row.values_at(:user_id, :tab, :requested_by_id, :requested_tab)
  end

  test "a release after the row was handed over deletes nothing" do
    claim(@olga, A)
    Editing::Reservation.request(subject: @subject, by: @dana, tab: B)

    handed, released = behind(
      -> { Editing::Reservation.hand_over(subject: @subject, user: @olga, tab: A) },
      -> { Editing::Reservation.release(subject: @subject, user: @olga, tab: A) }
    )

    assert handed
    assert_not released
    assert_equal [ @dana.id, B ], row.values_at(:user_id, :tab)
  end
end
