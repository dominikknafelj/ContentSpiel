require "test_helper"

# The one sign-in decision, on a throttle store of the test's own: the bot
# check before the reservation, the reservation before the password, and
# what each outcome carries.
class SignIn::PasswordAttemptTest < ActiveSupport::TestCase
  EMAIL = "ann@example.org".freeze
  PASSWORD = "password12345".freeze
  ADDRESS = "203.0.113.7".freeze
  HOSTNAME = SignInHelper::BOT_CHECK_HOSTNAME
  Trip = SignIn::Protection::Throttle::Trip

  # A store that yields the thread around every call, so attempts on
  # several threads interleave between their reads and writes.
  class Interleaving < ActiveSupport::Cache::MemoryStore
    %i[read write increment decrement exist? delete_multi].each do |name|
      define_method(name) do |*args, **options|
        Thread.pass
        super(*args, **options).tap { Thread.pass }
      end
    end
  end

  setup do
    freeze_time
    @user = User.create!(email_address: EMAIL, password: PASSWORD)
    @store = ActiveSupport::Cache::MemoryStore.new
    @throttle = SignIn::Protection::Throttle.new(store: @store)
  end

  def attempt(email: EMAIL, password: "wrong", address: ADDRESS, token: nil, throttle: @throttle, bot_check: SignIn::Protection::BotCheck.current, allowed: nil)
    options = { allowed: allowed }.compact
    SignIn::PasswordAttempt.new(email: email, password: password, address: address, hostname: HOSTNAME,
      bot_check_token: token, throttle: throttle, bot_check: bot_check, **options).call
  end

  # How many times the block hashes a password (a check, or the hash
  # `authenticate_by` makes for an unknown address).
  def hashes
    count = 0
    lock = Mutex.new
    original = BCrypt::Engine.method(:hash_secret)
    counting = ->(*args, **options) { lock.synchronize { count += 1 }; original.call(*args, **options) }
    with_singleton_override(BCrypt::Engine, :hash_secret, counting) { yield }
    count
  end

  # Ann's count in the account bucket, or this address's in the wide one.
  def count_of(counter)
    digest = counter == :account ? VisitorAddress.digest(EMAIL, purpose: SignIn::Protection::Throttle::KEY_PURPOSE) : VisitorAddress.key(ADDRESS, purpose: SignIn::Protection::Throttle::KEY_PURPOSE)
    @store.read("sign_in:studio:#{counter}:#{digest}")
  end

  def spans_of(&block)
    exporter = Rails.application.config.x.otel_test_exporter
    exporter.reset
    Telemetry.tracer.in_span("test request", kind: :server, &block)
    exporter.finished_spans
  end

  test "the right password is ok and clears the count; a wrong one is refused and counts; the fifth refusal carries the trip that began" do
    3.times { assert_equal SignIn::Outcome.new(status: :refused, account: nil, trips: [], bot_check_due: false), attempt }
    assert_equal 3, count_of(:account)

    ok = attempt(password: PASSWORD)
    assert_equal :ok, ok.status
    assert_equal @user, ok.account
    assert_empty ok.trips
    assert_nil count_of(:account), "a success forgets the run"

    4.times { assert_empty attempt.trips }
    fifth = attempt
    assert_equal :refused, fifth.status
    assert_equal [ Trip.new(bucket: :account, level: 0, seconds: 60) ], fifth.trips
    assert_equal SignIn::Outcome.new(status: :locked, account: nil, trips: [ Trip.new(bucket: :account, level: 0, seconds: 60) ], bot_check_due: false), attempt
  end

  # REFUSALS BY RULE (`SignIn::Rules`): a right password for an account the
  # rule refuses is a wrong one in every way the attempt shows.
  def by_rule(**options) = attempt(allowed: SignIn::Rules.method(:password_allowed?), **options)

  test "under SSO_REQUIRED a non-owner's right password is refused like a wrong one, and counts in the account's bucket" do
    with_sso(required: true) do
      wrong = nil
      right = nil
      assert_equal 1, hashes { wrong = by_rule }
      assert_equal 1, hashes { right = by_rule(password: PASSWORD) }

      assert_equal wrong, right
      assert_equal SignIn::Outcome.new(status: :refused, account: nil, trips: [], bot_check_due: false), right
      assert_equal 2, count_of(:account)

      2.times { by_rule(password: PASSWORD) }
      assert_equal [ Trip.new(bucket: :account, level: 0, seconds: 60) ], by_rule(password: PASSWORD).trips, "the fifth right password closes the bucket as a wrong one would"
    end
  end

  test "an owner's right password still signs in under SSO_REQUIRED" do
    @user.update_columns(owner: true) # version: none (a test's setup)

    with_sso(required: true) do
      outcome = by_rule(password: PASSWORD)
      assert_equal :ok, outcome.status
      assert_equal @user, outcome.account
    end
  end

  test "a linked account's password is refused, required or not" do
    link_to_sso(@user)
    # The password a person could type (the console's, or one set before the
    # link), so the refusal is the rule's and not a digest nobody holds.
    @user.update_column(:password_digest, BCrypt::Password.create(PASSWORD, cost: BCrypt::Engine::MIN_COST)) # version: none (a test's setup)

    assert_equal :refused, by_rule(password: PASSWORD).status
    with_sso { assert_equal :refused, by_rule(password: PASSWORD).status }
    with_sso(required: true) { assert_equal :refused, by_rule(password: PASSWORD).status }
    assert_equal :ok, attempt(password: PASSWORD).status, "without the rule the same password signs in: the digest is the typed one"
  end

  test "a refusal by rule says nothing in the span that a wrong password does not" do
    with_sso(required: true) do
      wrong = spans_of { by_rule }.find { it.name == "auth.sign_in" }.attributes
      right = spans_of { by_rule(password: PASSWORD) }.find { it.name == "auth.sign_in" }.attributes

      assert_equal wrong, right
      assert_equal "refused", right["auth.outcome"]
      assert_equal true, right["auth.account_exists"]
    end
  end

  test "a right password for an account with a second factor is second_factor_required, keeps the account's count and gives the address's back" do
    @user.recovery_codes.create!(digest: RecoveryCode.digest(RecoveryCode.texts.first), generated_at: Time.current)

    outcome = nil
    spans = spans_of { outcome = attempt(password: PASSWORD) }

    assert_equal SignIn::Outcome.new(status: :second_factor_required, account: @user, trips: [], bot_check_due: false), outcome
    assert_equal 1, count_of(:account), "the run stands until the second step succeeds"
    assert_equal 0, count_of(:wide)
    assert_equal({ "auth.method" => "password", "auth.account_exists" => true, "auth.second_factor.required" => true, "auth.outcome" => "second_factor_required" },
      spans.find { |span| span.name == "auth.sign_in" }.attributes.to_h)
  end

  test "a failure that closes the account and the address carries both trips, the account's first" do
    45.times { |index| attempt(email: "person#{index}@example.org") }
    4.times { attempt }

    assert_equal [ Trip.new(bucket: :account, level: 0, seconds: 60), Trip.new(bucket: :address_wide, level: nil, seconds: 1.hour.to_i) ], attempt.trips
    assert_equal [ :address_wide ], attempt(email: "other@example.org").trips.map(&:bucket), "the wide bucket is asked first"
  end

  test "attempts at once on one account check five passwords before the lock" do
    throttle = SignIn::Protection::Throttle.new(store: Interleaving.new)
    outcomes = nil
    checked = hashes do
      outcomes = Array.new(16) { |index| Thread.new { attempt(address: "198.51.100.#{index + 1}", throttle: throttle) } }.map(&:value)
    end

    assert_equal 5, checked
    assert_equal 5, outcomes.count { |outcome| outcome.status == :refused }
    assert_equal 11, outcomes.count { |outcome| outcome.status == :locked }
    assert_equal 1, outcomes.sum { |outcome| outcome.status == :refused ? outcome.trips.size : 0 }, "one of the five closed the account"
  end

  test "a closed bucket is locked before any password is checked" do
    5.times { attempt }

    checked = hashes { assert_equal :locked, attempt(password: PASSWORD).status }
    assert_equal 0, checked
    assert_equal 1, hashes { attempt(email: "other@example.org") }, "another account's password is checked"
  end

  test "a due bot check without a token is bot_check_required, a refused one bot_check_failed, and neither checks a password or counts" do
    with_bot_check(:failed) do
      3.times { attempt(email: "person#{_1}@example.org") }
      wide = count_of(:wide)

      checked = hashes do
        [ nil, "", [ "a" ], "x" * 3000 ].each do |junk|
          assert_equal SignIn::Outcome.new(status: :bot_check_required, account: nil, trips: [], bot_check_due: true), attempt(token: junk, password: PASSWORD)
        end
        assert_equal SignIn::Outcome.new(status: :bot_check_failed, account: nil, trips: [], bot_check_due: true), attempt(token: "token", password: PASSWORD)
      end

      assert_equal 0, checked
      assert_equal 1, bot_check_requests.size, "only the usable token is sent"
      assert_equal wide, count_of(:wide)
      assert_nil count_of(:account)
    end
  end

  test "with Cloudflare unreachable the attempt goes on to the password, and the span says unavailable" do
    with_bot_check(:unavailable) do
      3.times { attempt }
      outcome = nil
      spans = spans_of { outcome = attempt(token: "token", password: PASSWORD) }

      assert_equal :ok, outcome.status
      assert_equal "unavailable", spans.find { |span| span.name == "auth.bot_check" }.attributes["auth.bot_check.result"]
      sign_in = spans.find { |span| span.name == "auth.sign_in" }
      assert_equal({ "auth.method" => "password", "auth.bot_check.required" => true, "auth.account_exists" => true, "auth.outcome" => "ok" }, sign_in.attributes.to_h)
    end
  end

  test "without Turnstile configured no check is ever due and the throttles still stand" do
    assert_nil SignIn::Protection::BotCheck.current

    4.times { assert_not attempt.bot_check_due }
    assert_equal [ :account ], attempt.trips.map(&:bucket)
    assert_equal :locked, attempt.status

    spans = spans_of { attempt(email: "other@example.org") }
    assert_equal({ "auth.method" => "password", "auth.account_exists" => false, "auth.outcome" => "refused" },
      spans.find { |span| span.name == "auth.sign_in" }.attributes.to_h)
  end

  test "an empty password checks none, and the span says nothing of the account" do
    spans = spans_of { assert_equal :refused, attempt(password: "").status }
    assert_equal({ "auth.method" => "password", "auth.outcome" => "refused" }, spans.find { |span| span.name == "auth.sign_in" }.attributes.to_h)
    assert_equal 1, count_of(:account), "it counts as any refusal"
  end

  test "the identifier is the email as User normalises it, and a list or a hash is the empty one" do
    assert_equal EMAIL, SignIn::PasswordAttempt.new(email: " Ann@Example.ORG ", password: "", address: ADDRESS, hostname: HOSTNAME, bot_check_token: nil).identifier
    [ [ EMAIL ], { "a" => EMAIL }, nil, "ann\0@example.org", "\xFF@example.org".b.force_encoding("UTF-8") ].each do |junk|
      assert_equal "", SignIn::PasswordAttempt.new(email: junk, password: "", address: ADDRESS, hostname: HOSTNAME, bot_check_token: nil).identifier
    end
  end
end
