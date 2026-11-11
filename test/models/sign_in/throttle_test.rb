require "test_helper"

# The sign-in throttle's counters, on a store of the test's own: the account
# bucket's back-off, the wide address cap, the bot check's due mark and the
# lock-out notice's hour. An attempt is a `reserve`; one whose password was
# wrong is told nothing more, one whose password was right is followed by
# `record_success`.
class SignIn::ThrottleTest < ActiveSupport::TestCase
  EMAIL = "ann@example.org".freeze
  ADDRESS = "203.0.113.7".freeze
  Trip = SignIn::Throttle::Trip

  # A store whose every count fails as Solid Cache's failsafe answers one.
  class FailingCounts < ActiveSupport::Cache::MemoryStore
    def increment(...) = nil
    def decrement(...) = nil
  end

  # A store that yields the thread around every call, so attempts on
  # several threads interleave between their read, increment and write.
  class Interleaving < ActiveSupport::Cache::MemoryStore
    %i[read write increment decrement exist?].each do |name|
      define_method(name) do |*args, **options|
        Thread.pass
        super(*args, **options).tap { Thread.pass }
      end
    end
  end

  setup do
    freeze_time
    @store = ActiveSupport::Cache::MemoryStore.new
    @throttle = SignIn::Throttle.new(store: @store)
  end

  def attempt(identifier: EMAIL, address: ADDRESS, throttle: @throttle, device: nil)
    throttle.reserve(identifier: identifier, address: address, device: device)
  end

  def attempts(count, **options) = Array.new(count) { attempt(**options) }.last

  def keys(store = @store) = store.instance_variable_get(:@data).keys
  def count_of(counter, store = @store) = store.read(keys(store).find { |key| key.include?(":#{counter}:") })

  test "lock_seconds is nil below five failures, then 60, 120, 240 … and 3600 from the eleventh" do
    assert_equal [ nil ] * 4 + [ 60, 120, 240, 480, 960, 1920, 3600, 3600 ], (1..12).map { |count| SignIn::Throttle.lock_seconds(count) }
  end

  test "the fifth attempt goes on and closes the account for a minute, and the bucket opens again after it" do
    4.times { assert_equal SignIn::Throttle::Reservation.new(refused_by: nil, closes: []), attempt }

    fifth = attempt
    assert fifth.ok?
    assert_equal [ Trip.new(bucket: :account, level: 0, seconds: 60) ], fifth.closes
    assert_equal Trip.new(bucket: :account, level: 0, seconds: 60), attempt.refused_by
    assert attempt(identifier: "bea@example.org").ok?, "another account is open"

    travel 30.seconds
    assert_equal 30, attempt.refused_by.seconds

    travel 31.seconds
    sixth = attempt
    assert sixth.ok?
    assert_equal [ Trip.new(bucket: :account, level: 1, seconds: 120) ], sixth.closes
  end

  test "an attempt during the lock checks no password and leaves the lock as it was" do
    attempts(5)
    lock_key = keys.find { |key| key.include?(":account_lock:") }
    lock = @store.read(lock_key)

    travel 10.seconds
    2.times { assert_equal :account, attempt.refused_by.bucket }

    assert_equal 5, count_of(:account)
    assert_equal 5, count_of(:wide), "the refused attempts took their address count back"
    assert_equal lock, @store.read(lock_key)
    travel 51.seconds
    assert attempt.ok?, "the lock ends when it was set to"
  end

  test "a success clears the account's count and lock, and the next attempt counts from one" do
    attempts(5)
    assert_nil @throttle.record_success(identifier: EMAIL, address: ADDRESS)

    assert_equal [], attempt.closes
    assert_equal 1, count_of(:account)
    attempts(3)
    assert_equal [ 0 ], attempt.closes.map(&:level)
  end

  test "an account's attempts are forgotten 24 hours after the run's first" do
    attempts(2)
    travel 23.hours
    attempts(2)
    assert_equal 4, count_of(:account)

    travel 1.hour + 1.second
    assert_empty attempts(4).closes, "the run began again with the 24 hours"
    assert_equal 4, count_of(:account)
  end

  test "a lock that outlives its run's count keeps its level" do
    start = Time.current
    10.times { |index| attempt; travel SignIn::Throttle.lock_seconds(index + 1).to_i + 1 }

    travel_to start + 23.hours + 59.minutes
    assert_equal [ Trip.new(bucket: :account, level: 6, seconds: 3600) ], attempt.closes, "the eleventh, inside the run"

    travel 2.minutes
    assert_nil count_of(:account), "the run's count is forgotten"
    assert_equal Trip.new(bucket: :account, level: 6, seconds: 3480), attempt.refused_by
  end

  test "the fiftieth attempt from an address closes it until the hour ends, whatever accounts it tried" do
    49.times { |index| assert_equal [], attempt(identifier: "person#{index}@example.org").closes }

    travel 20.minutes
    fiftieth = attempt(identifier: "last@example.org")
    assert fiftieth.ok?
    assert_equal [ Trip.new(bucket: :address_wide, level: nil, seconds: 40.minutes.to_i) ], fiftieth.closes
    assert_equal Trip.new(bucket: :address_wide, level: nil, seconds: 40.minutes.to_i), attempt(identifier: "someone@example.org").refused_by
    assert_equal 50, count_of(:wide), "a refused attempt is not counted"
    assert attempt(identifier: "someone@example.org", address: "203.0.113.8").ok?, "another address is open"

    travel 40.minutes + 1.second
    assert attempt(identifier: "someone@example.org").ok?
  end

  test "a success takes back only its own count from the address" do
    48.times { |index| attempt(identifier: "person#{index}@example.org") }
    attempt(identifier: "right@example.org")
    @throttle.record_success(identifier: "right@example.org", address: ADDRESS)
    assert_equal 48, count_of(:wide)

    assert_equal [], attempt(identifier: "next@example.org").closes
    assert_equal :address_wide, attempt(identifier: "last@example.org").closes.sole.bucket
  end

  test "an attempt that closes both buckets answers both, the account's first" do
    45.times { |index| attempt(identifier: "person#{index}@example.org") }
    attempts(4)

    assert_equal [ Trip.new(bucket: :account, level: 0, seconds: 60), Trip.new(bucket: :address_wide, level: nil, seconds: 1.hour.to_i) ], attempt.closes
    assert attempt(identifier: "other@example.org", address: "198.51.100.1").ok?
  end

  test "the wide bucket is asked first" do
    attempts(5)
    45.times { |index| attempt(identifier: "person#{index}@example.org") }
    assert_equal :address_wide, attempt.refused_by.bucket
  end

  test "the bot check is due after three attempts from the address or for the account in 15 minutes, and not after the window" do
    attempts(2, identifier: "one@example.org")
    assert_not @throttle.bot_check_due?(address: ADDRESS)
    attempt(identifier: "two@example.org")
    assert @throttle.bot_check_due?(address: ADDRESS)
    assert @throttle.bot_check_due?(address: ADDRESS, identifier: "three@example.org")

    travel 15.minutes + 1.second
    assert_not @throttle.bot_check_due?(address: ADDRESS)

    attempt(address: "198.51.100.1")
    attempt(address: "198.51.100.2")
    attempt(address: "198.51.100.3")
    assert_not @throttle.bot_check_due?(address: "198.51.100.4")
    assert @throttle.bot_check_due?(address: "198.51.100.4", identifier: EMAIL), "the account's own three attempts"

    travel 15.minutes + 1.second
    assert_not @throttle.bot_check_due?(address: "198.51.100.4", identifier: EMAIL)
  end

  test "a known device counts in a bucket of its own: the account's lock does not refuse it, and its own lock closes it alone" do
    attempts(5)
    assert_equal :account, attempt.refused_by.bucket

    device = attempt(device: "d" * 32)
    assert device.ok?, "the account's lock does not hold a known device"
    3.times { assert attempt(device: "d" * 32).ok? }
    assert_equal [ Trip.new(bucket: :device, level: 0, seconds: 60) ], attempt(device: "d" * 32).closes
    assert_equal Trip.new(bucket: :device, level: 0, seconds: 60), attempt(device: "d" * 32).refused_by
    assert attempt(device: "e" * 32).ok?, "another device of the account is open"
    assert_equal 5, count_of(:account), "a device's attempts are not the account's"

    travel 61.seconds
    assert attempt.ok?, "the account's own lock ended as it was set"
  end

  test "a success on a known device forgets the device's run and leaves the account's; clear forgets the account's" do
    4.times { attempt(device: "d" * 32) }
    attempts(5)
    @throttle.record_success(identifier: EMAIL, address: ADDRESS, device: "d" * 32)
    assert_equal :account, attempt.refused_by.bucket, "the account's lock stands"
    assert_empty Array.new(4) { attempt(device: "d" * 32) }.flat_map(&:closes), "the device's run began again"

    assert_nil @throttle.clear(identifier: EMAIL)
    assert attempt.ok?
    assert_equal 1, count_of(:account)
    assert_not @throttle.bot_check_due?(address: "198.51.100.9", identifier: EMAIL), "the account's bot-check count is forgotten too"
  end

  test "clear opens every known device's lock and count of the account at once, and no other account's" do
    5.times { attempt(device: "d" * 32) }
    5.times { attempt(identifier: "bea@example.org", device: "d" * 32) }
    assert_equal :device, attempt(device: "d" * 32).refused_by.bucket

    @throttle.clear(identifier: EMAIL)
    assert_empty Array.new(4) { attempt(device: "d" * 32) }.map(&:refused_by).compact, "the device's run began again"
    assert_equal [ 0 ], attempt(device: "d" * 32).closes.map(&:level)
    assert_equal :device, attempt(identifier: "bea@example.org", device: "d" * 32).refused_by.bucket, "another account's device lock stands"
  end

  test "a device's bucket is decided in an auth.throttle span of its own name" do
    exporter = Rails.application.config.x.otel_test_exporter
    exporter.reset
    Telemetry.tracer.in_span("test request", kind: :server) { attempt(device: "d" * 32) }

    assert_equal %w[address_wide device], exporter.finished_spans.select { |span| span.name == "auth.throttle" }.map { |span| span.attributes["auth.bucket"] }
  end

  test "reserve_address counts in the wide bucket alone, so an account's lock never refuses it, and release_address takes back its wide count alone" do
    attempts(5)
    assert_equal :account, attempt.refused_by.bucket

    reservation = @throttle.reserve_address(address: ADDRESS)
    assert_equal SignIn::Throttle::Reservation.new(refused_by: nil, closes: []), reservation
    assert_equal 6, count_of(:wide)
    assert_equal 5, count_of(:account), "the account's run is not counted"

    assert_nil @throttle.release_address(address: ADDRESS)
    assert_equal 5, count_of(:wide)
    assert_equal 5, count_of(:bot_address), "reserve_address counted no bot check, so none is taken back"
    assert_equal :account, attempt.refused_by.bucket, "the account's lock stands"

    45.times { @throttle.reserve_address(address: ADDRESS) }
    assert_equal :address_wide, @throttle.reserve_address(address: ADDRESS).refused_by.bucket
  end

  test "passkey sign-ins again and again leave the address's bot-check count as it was, and no count goes below 0" do
    attempt
    5.times do
      @throttle.reserve_address(address: ADDRESS)
      @throttle.release_address(address: ADDRESS)
    end
    assert_equal 1, count_of(:bot_address)
    assert_equal 1, count_of(:wide)

    3.times { @throttle.release_address(address: ADDRESS) }
    assert_equal 0, count_of(:wide), "a take-back of more than was counted stops at 0"
    attempt
    assert_equal 1, count_of(:wide)
  end

  test "await_second_proof takes back the lock its own reservation wrote and keeps the count; a lock written before it stands" do
    attempts(4)
    reservation = attempt
    assert_equal [ Trip.new(bucket: :account, level: 0, seconds: 60) ], reservation.closes

    assert_nil @throttle.await_second_proof(reservation, identifier: EMAIL, address: ADDRESS)
    assert_equal 5, count_of(:account), "the run's count stands"
    assert_equal 4, count_of(:wide), "the address's counts are taken back as a success's are"
    assert_equal 4, count_of(:bot_address)
    sixth = attempt
    assert sixth.ok?, "the lock it wrote is gone"
    assert_equal [ Trip.new(bucket: :account, level: 1, seconds: 120) ], sixth.closes, "the next attempt writes the next lock itself"
    assert_equal :account, attempt.refused_by.bucket, "and it stands"

    device = "d" * 32
    attempts(4, device: device)
    reservation = attempt(device: device)
    @throttle.await_second_proof(reservation, identifier: EMAIL, address: ADDRESS, device: device)
    assert attempt(device: device).ok?, "a known device's lock is taken back the same way"
    assert_equal :account, attempt.refused_by.bucket, "the account's own lock was not touched"
  end

  test "a notice is due once an hour per account" do
    assert @throttle.notice_due?(identifier: EMAIL)
    assert_not @throttle.notice_due?(identifier: EMAIL)
    assert @throttle.notice_due?(identifier: "bea@example.org")

    travel 1.hour + 1.second
    assert @throttle.notice_due?(identifier: EMAIL)
  end

  test "two scopes count apart, and the store holds neither the address nor the IP" do
    members = SignIn::Throttle.new(scope: "members", store: @store)
    attempts(5)
    assert attempt(throttle: members).ok?
    @throttle.bot_check_due?(address: ADDRESS)
    @throttle.notice_due?(identifier: EMAIL)

    assert keys.any? { |key| key.include?(":members:") } && keys.any? { |key| key.include?(":studio:") }, keys.inspect
    keys.each do |key|
      [ EMAIL, "ann", "example.org", ADDRESS, "203.0.113" ].each { |text| assert_not_includes key, text }
      assert_match(/:\h{64}\z/, key)
    end
  end

  test "a count the store cannot make opens every bucket, and nothing raises" do
    throttle = SignIn::Throttle.new(store: FailingCounts.new)

    60.times { assert_equal SignIn::Throttle::Reservation.new(refused_by: nil, closes: []), attempt(throttle: throttle) }
    assert_not throttle.bot_check_due?(address: ADDRESS, identifier: EMAIL)
    assert_nil throttle.record_success(identifier: EMAIL, address: ADDRESS)
  end

  test "attempts at once on one account let exactly five through before the lock" do
    store = Interleaving.new
    throttle = SignIn::Throttle.new(store: store)

    reservations = Array.new(24) { |index| Thread.new { throttle.reserve(identifier: EMAIL, address: "198.51.100.#{index + 1}") } }.map(&:value)

    assert_equal 5, reservations.count(&:ok?)
    assert_equal 1, reservations.sum { |reservation| reservation.closes.size }, "one of the five closed the account"
    assert reservations.reject(&:ok?).all? { |reservation| reservation.refused_by.bucket == :account }
    assert_equal 5, count_of(:account, store), "every refused attempt took its count back"
  end

  test "attempts at once from one address let exactly fifty through" do
    store = Interleaving.new
    throttle = SignIn::Throttle.new(store: store)

    reservations = Array.new(70) { |index| Thread.new { throttle.reserve(identifier: "person#{index}@example.org", address: ADDRESS) } }.map(&:value)

    assert_equal 50, reservations.count(&:ok?)
    assert_equal [ :address_wide ], reservations.flat_map(&:closes).map(&:bucket)
    assert_equal 50, count_of(:wide, store)
  end

  test "each bucket decided is one span, tripped when it refused the attempt or the attempt closed it" do
    exporter = Rails.application.config.x.otel_test_exporter
    attempts(4)
    exporter.reset

    Telemetry.tracer.in_span("test request", kind: :server) do
      attempt
      attempt
    end

    spans = exporter.finished_spans.select { |span| span.name == "auth.throttle" }
    assert_equal [
      { "auth.bucket" => "address_wide", "auth.tripped" => false },
      { "auth.bucket" => "account", "auth.tripped" => true, "auth.backoff_level" => 0 },
      { "auth.bucket" => "address_wide", "auth.tripped" => false },
      { "auth.bucket" => "account", "auth.tripped" => true, "auth.backoff_level" => 0 }
    ], spans.map { |span| span.attributes.to_h }
    assert spans.all? { |span| span.kind == :internal }
  end
end
