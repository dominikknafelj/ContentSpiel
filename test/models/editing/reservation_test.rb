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

  test "a request is written on another tab's live row, keeps its time when asked again, and is nothing on one's own or an expired row" do
    claim(@olga, A)

    assert_not Editing::Reservation.request(subject: @block, by: @olga, tab: A, now: @now)
    assert Editing::Reservation.request(subject: @block, by: @dana, tab: B, now: @now + 1)
    assert Editing::Reservation.request(subject: @block, by: @dana, tab: B, now: @now + 3)
    assert_equal [ @dana.id, B, @now + 1 ], Editing::Reservation.sole.values_at(:requested_by_id, :requested_tab, :requested_at)
    assert_not Editing::Reservation.request(subject: @block, by: @dana, tab: B, now: @now + Editing::HOLD + 5)
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
    assert Editing::Reservation.request(subject: @block, by: leaver, tab: "tab-cccccccc", now: @now + 1)
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

  teardown { Editing::Reservation.delete_all } # version: none (a test's own rows)

  def subject_and_record = [ ContentBlock.new(id: 9_000_000_001), Page.new(id: 9_000_000_001) ]

  def at_once(callers)
    gate = Queue.new
    threads = callers.map do |caller|
      Thread.new { ActiveRecord::Base.connection_pool.with_connection { gate.pop; caller.call } }
    end
    callers.size.times { gate << :go }
    threads.map(&:value)
  end

  test "two tabs claiming a free subject at once: one takes it, the other is refused, and there is one row" do
    subject, record = subject_and_record
    20.times do
      Editing::Reservation.delete_all # version: none (a test's own rows)
      results = at_once([ [ users(:one), "tab-aaaaaaaa" ], [ users(:two), "tab-bbbbbbbb" ] ].map do |user, tab|
        -> { Editing::Reservation.claim(subject:, record:, user:, tab:) }
      end)

      assert_equal %i[refused taken], results.sort
      assert_equal 1, Editing::Reservation.count
    end
  end

  test "a holder renewing and a stranger claiming at the boundary: exactly one holds afterwards" do
    subject, record = subject_and_record
    20.times do
      Editing::Reservation.delete_all # version: none (a test's own rows)
      start = Time.current - Editing::HOLD
      Editing::Reservation.claim(subject:, record:, user: users(:one), tab: "tab-aaaaaaaa", now: start)
      results = at_once([
        -> { Editing::Reservation.claim(subject:, record:, user: users(:one), tab: "tab-aaaaaaaa") },
        -> { Editing::Reservation.claim(subject:, record:, user: users(:two), tab: "tab-bbbbbbbb") }
      ])

      assert_equal 1, results.count(:taken), results.inspect
      assert_equal 1, results.count(:refused), results.inspect
      assert_equal 1, Editing::Reservation.count
    end
  end
end
