require "test_helper"

# The sign-in throttle's counters, on a store of the test's own: the account
# bucket's back-off, the wide address cap, the bot check's due mark and the
# lock-out notice's hour.
class SignIn::ThrottleTest < ActiveSupport::TestCase
  EMAIL = "ann@example.org".freeze
  ADDRESS = "203.0.113.7".freeze

  setup do
    freeze_time
    @store = ActiveSupport::Cache::MemoryStore.new
    @throttle = SignIn::Throttle.new(store: @store)
  end

  def fail_times(count, identifier: EMAIL, address: ADDRESS, throttle: @throttle)
    Array.new(count) { throttle.record_failure(identifier: identifier, address: address) }.last
  end

  def account_count = @store.read(@store.instance_variable_get(:@data).keys.find { |key| key.include?(":account:") })

  test "lock_seconds is nil below five failures, then 60, 120, 240 … and 3600 from the eleventh" do
    assert_equal [ nil ] * 4 + [ 60, 120, 240, 480, 960, 1920, 3600, 3600 ], (1..12).map { |failures| SignIn::Throttle.lock_seconds(failures) }
  end

  test "the fifth failure closes the account for a minute, and the bucket opens again after it" do
    assert_empty fail_times(4)
    assert_nil @throttle.closed(identifier: EMAIL, address: ADDRESS)

    trips = @throttle.record_failure(identifier: EMAIL, address: ADDRESS)
    assert_equal [ SignIn::Throttle::Trip.new(bucket: :account, level: 0, seconds: 60) ], trips
    assert_equal SignIn::Throttle::Trip.new(bucket: :account, level: 0, seconds: 60), @throttle.closed(identifier: EMAIL, address: ADDRESS)
    assert_nil @throttle.closed(identifier: "bea@example.org", address: ADDRESS), "another account is open"

    travel 30.seconds
    assert_equal 30, @throttle.closed(identifier: EMAIL, address: ADDRESS).seconds

    travel 31.seconds
    assert_nil @throttle.closed(identifier: EMAIL, address: ADDRESS)
    assert_equal [ SignIn::Throttle::Trip.new(bucket: :account, level: 1, seconds: 120) ], @throttle.record_failure(identifier: EMAIL, address: ADDRESS)
  end

  test "an attempt during the lock checks no password and leaves the lock as it was" do
    fail_times(5)
    lock_key = @store.instance_variable_get(:@data).keys.find { |key| key.include?(":account_lock:") }
    lock_end = @store.read(lock_key)

    travel 10.seconds
    2.times { assert_equal :account, @throttle.closed(identifier: EMAIL, address: ADDRESS).bucket }

    assert_equal 5, account_count
    assert_equal lock_end, @store.read(lock_key)
    travel 51.seconds
    assert_nil @throttle.closed(identifier: EMAIL, address: ADDRESS), "the lock ends when it was set to"
  end

  test "a success clears the account's count and lock, and the next failure counts from one" do
    fail_times(5)
    assert_nil @throttle.record_success(identifier: EMAIL)

    assert_nil @throttle.closed(identifier: EMAIL, address: ADDRESS)
    assert_empty fail_times(1)
    assert_equal 1, account_count
    assert_empty fail_times(3)
    assert_equal [ 0 ], fail_times(1).map(&:level)
  end

  test "an account's failures are forgotten 24 hours after the run's first" do
    fail_times(2)
    travel 23.hours
    fail_times(2)
    assert_equal 4, account_count

    travel 1.hour + 1.second
    assert_empty fail_times(4), "the run began again with the 24 hours"
    assert_equal 4, account_count
  end

  test "the fiftieth failure from an address closes it until the hour ends, whatever accounts it tried" do
    49.times { |index| assert_empty @throttle.record_failure(identifier: "person#{index}@example.org", address: ADDRESS) }
    assert_nil @throttle.closed(identifier: "someone@example.org", address: ADDRESS)

    travel 20.minutes
    trips = @throttle.record_failure(identifier: "last@example.org", address: ADDRESS)
    assert_equal [ SignIn::Throttle::Trip.new(bucket: :address_wide, level: nil, seconds: 40.minutes.to_i) ], trips
    assert_equal :address_wide, @throttle.closed(identifier: "someone@example.org", address: ADDRESS).bucket
    assert_nil @throttle.closed(identifier: "someone@example.org", address: "203.0.113.8"), "another address is open"

    travel 40.minutes + 1.second
    assert_nil @throttle.closed(identifier: "someone@example.org", address: ADDRESS)
  end

  test "a failure that closes both buckets answers both, the account's first" do
    45.times { |index| @throttle.record_failure(identifier: "person#{index}@example.org", address: ADDRESS) }
    assert_empty fail_times(4)

    assert_equal [ SignIn::Throttle::Trip.new(bucket: :account, level: 0, seconds: 60),
      SignIn::Throttle::Trip.new(bucket: :address_wide, level: nil, seconds: 1.hour.to_i) ], fail_times(1)
    assert_equal [], fail_times(1, identifier: "other@example.org", address: "198.51.100.1")
  end

  test "a lock that outlives its run's count keeps its level" do
    fail_times(10)
    travel 23.hours + 59.minutes
    assert_equal [ SignIn::Throttle::Trip.new(bucket: :account, level: 6, seconds: 3600) ], fail_times(1), "the 11th failure, inside the run"

    travel 2.minutes
    assert_nil account_count, "the run's count is forgotten"
    assert_equal SignIn::Throttle::Trip.new(bucket: :account, level: 6, seconds: 3480), @throttle.closed(identifier: EMAIL, address: ADDRESS)
  end

  test "the wide bucket is asked first" do
    50.times { @throttle.record_failure(identifier: EMAIL, address: ADDRESS) }
    assert_equal :address_wide, @throttle.closed(identifier: EMAIL, address: ADDRESS).bucket
  end

  test "the bot check is due after three failures from the address or for the account in 15 minutes, and not after the window" do
    fail_times(2, identifier: "one@example.org")
    assert_not @throttle.bot_check_due?(address: ADDRESS)
    fail_times(1, identifier: "two@example.org")
    assert @throttle.bot_check_due?(address: ADDRESS)
    assert @throttle.bot_check_due?(address: ADDRESS, identifier: "three@example.org")

    travel 15.minutes + 1.second
    assert_not @throttle.bot_check_due?(address: ADDRESS)

    fail_times(1, address: "198.51.100.1")
    fail_times(1, address: "198.51.100.2")
    fail_times(1, address: "198.51.100.3")
    assert_not @throttle.bot_check_due?(address: "198.51.100.4")
    assert @throttle.bot_check_due?(address: "198.51.100.4", identifier: EMAIL), "the account's own three failures"

    travel 15.minutes + 1.second
    assert_not @throttle.bot_check_due?(address: "198.51.100.4", identifier: EMAIL)
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
    fail_times(5)
    assert_nil members.closed(identifier: EMAIL, address: ADDRESS)
    assert_empty fail_times(4, throttle: members)
    @throttle.bot_check_due?(address: ADDRESS)
    @throttle.notice_due?(identifier: EMAIL)

    keys = @store.instance_variable_get(:@data).keys
    assert keys.any? { |key| key.include?(":members:") } && keys.any? { |key| key.include?(":studio:") }, keys.inspect
    keys.each do |key|
      [ EMAIL, "ann", "example.org", ADDRESS, "203.0.113" ].each { |text| assert_not_includes key, text }
      assert_match(/:\h{64}\z/, key)
    end
  end

  test "closed makes one span per bucket asked, and record_failure one per bucket it closed" do
    exporter = Rails.application.config.x.otel_test_exporter
    fail_times(4)
    exporter.reset

    Telemetry.tracer.in_span("test request", kind: :server) do
      @throttle.closed(identifier: EMAIL, address: ADDRESS)
      @throttle.record_failure(identifier: EMAIL, address: ADDRESS)
    end

    spans = exporter.finished_spans.select { |span| span.name == "auth.throttle" }
    assert_equal [
      { "auth.bucket" => "address_wide", "auth.tripped" => false },
      { "auth.bucket" => "account", "auth.tripped" => false },
      { "auth.bucket" => "account", "auth.tripped" => true, "auth.backoff_level" => 0 }
    ], spans.map { |span| span.attributes.to_h }
    assert spans.all? { |span| span.kind == :internal }
  end
end
