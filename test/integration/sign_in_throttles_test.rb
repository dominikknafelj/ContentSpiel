require "test_helper"

# Sign-in's throttles and bot check through the real controller: what each
# outcome answers, what it audits, and that a known and an unknown address
# are answered alike.
class SignInThrottlesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  EMAIL = "ann@example.org".freeze
  UNKNOWN = "nobody@example.org".freeze
  PASSWORD = "password12345".freeze
  # Past the per-address rate limit's pace (10 in 3 minutes), so a test
  # that needs more attempts from one address meets only the buckets.
  PACE = 20.seconds

  setup do
    freeze_time
    @user = User.create!(email_address: EMAIL, password: PASSWORD)
  end

  def attempt(email, password: "wrong", paced: true, **params_and_options)
    headers = params_and_options.delete(:headers) || {}
    env = params_and_options.delete(:env) || {}
    post admin_sign_in_path, params: { email_address: email, password: password, **params_and_options }, headers: headers, env: env
    travel PACE if paced
  end

  def wrong_attempts(count, email = EMAIL, **options) = count.times { attempt(email, **options) }

  # How many times the block hashes a password.
  def hashes
    count = 0
    original = BCrypt::Engine.method(:hash_secret)
    with_singleton_override(BCrypt::Engine, :hash_secret, ->(*args, **options) { count += 1; original.call(*args, **options) }) { yield }
    count
  end

  # One attempt's whole answer, from a fresh session: what a bot can read
  # of it, and the work it took. `statements` compares the SQL's shape, not
  # its values: binds are `$n` in the text, so an insert's ids and the email
  # typed never differ in it, and need no stripping. `jobs` are the classes
  # it enqueued, whose arguments differ by the email alone.
  def answer_to(email, password: "wrong", **params)
    reset!
    statements = nil
    queued = enqueued_jobs.size
    hashed = hashes { statements = capture_sql { attempt(email, password: password, **params) } }
    answer = {
      status: response.status, location: response.location, flash: flash[:alert], cookies: cookies.to_hash.keys.sort,
      statements: statements, hashes: hashed, jobs: enqueued_jobs.drop(queued).map { it[:job].name }
    }
    follow_redirect!
    answer.merge(page: response.body.gsub(/(name="authenticity_token" value=|name="csrf-token" content=|nonce=)"[^"]*"/, '\1""'))
  end

  def locked_events = Audit::Event.where(action: "session.locked").order(:id)

  test "a refused sign-in answers the same for a known and an unknown address: status, location, flash, page, cookie names, statements and one password hash each" do
    known = answer_to(EMAIL)
    unknown = answer_to(UNKNOWN)

    assert_equal known, unknown
    assert_equal 302, known[:status]
    assert_equal I18n.t("admin.sessions.refused"), known[:flash]
    assert_equal 1, known[:hashes]
    assert known[:statements].any? { |sql| sql.include?("audit_events") }, "the refusal is audited"
  end

  test "the right password typed with an email that has no account answers as a wrong one for a known email" do
    known = answer_to(EMAIL)
    unknown = answer_to(UNKNOWN, password: PASSWORD)

    assert_equal known, unknown
    assert_equal I18n.t("admin.sessions.refused"), known[:flash]
    assert_equal 1, known[:hashes]
  end

  # A refusal by rule (`SignIn::Rules`): a linked account, or a non-owner
  # under SSO_REQUIRED, typing its right password is answered as another
  # account typing a wrong one, with the same work.
  test "a refused-by-rule right password answers as a wrong one: status, body, redirect and the same authenticate_by" do
    other = User.create!(email_address: "ben@example.org", password: PASSWORD)
    link_to_sso(@user)
    @user.update_column(:password_digest, BCrypt::Password.create(PASSWORD, cost: BCrypt::Engine::MIN_COST)) # version: none (a test's setup)

    wrong = answer_to(other.email_address)
    linked = answer_to(EMAIL, password: PASSWORD)
    assert_equal wrong, linked
    assert_equal I18n.t("admin.sessions.refused"), linked[:flash]
    assert_equal 1, linked[:hashes]

    with_sso(required: true) do
      third = User.create!(email_address: "cleo@example.org", password: PASSWORD)
      fourth = User.create!(email_address: "dan@example.org", password: PASSWORD)
      assert_equal answer_to(third.email_address), answer_to(fourth.email_address, password: PASSWORD)
    end
    assert_not Session.exists?, "nobody was signed in"
    assert_equal 4, Audit::Event.where(action: "session.failed").count
  end

  test "a required and a refused bot check answer the same for a known and an unknown address, and check no password" do
    with_bot_check(:failed) do
      3.times { |index| attempt("person#{index}@example.org") }

      required = [ answer_to(EMAIL, password: PASSWORD), answer_to(UNKNOWN) ]
      assert_equal(*required)
      failed = [ answer_to(EMAIL, password: PASSWORD, "cf-turnstile-response" => "token"), answer_to(UNKNOWN, "cf-turnstile-response" => "token") ]
      assert_equal(*failed)

      [ required.first, failed.first ].each do |answer|
        assert_equal I18n.t("admin.sessions.bot_check"), answer[:flash]
        assert_equal 0, answer[:hashes]
        assert_empty answer[:statements]
      end
    end
  end

  test "a limited address answers the same for a known and an unknown address, past the rate limit and past the wide cap" do
    10.times { |index| attempt("person#{index}@example.org", paced: false) }
    limited = [ answer_to(EMAIL, password: PASSWORD), answer_to(UNKNOWN) ]
    assert_equal(*limited)
    assert_equal I18n.t("admin.sessions.limited"), limited.first[:flash]

    travel 3.minutes
    40.times { |index| attempt("other#{index}@example.org") }
    wide = [ answer_to(EMAIL, password: PASSWORD), answer_to(UNKNOWN) ]
    assert_equal(*wide)
    assert_equal I18n.t("admin.sessions.limited"), wide.first[:flash]
    assert_equal 0, wide.first[:hashes]
    assert_empty wide.first[:statements]
  end

  test "an email Postgres would refuse is an ordinary refusal, counted in the empty address's bucket, never a 500" do
    [ "ann\0@example.org", "\0", "ann@example.org\0" ].each do |typed|
      attempt(typed, password: PASSWORD)
      assert_redirected_to admin_sign_in_path
      assert_equal I18n.t("admin.sessions.refused"), flash[:alert]
    end
    assert_equal [ {} ] * 3, Audit::Event.where(action: "session.failed").map(&:metadata)

    # Bytes that are no UTF-8 are Rails' own 400, before the action: nothing
    # is counted or recorded.
    assert_no_difference -> { Audit::Event.count } do
      attempt("\xFF@example.org".b, password: PASSWORD)
    end
    assert_response :bad_request

    2.times { attempt("ann\0@example.org") }
    assert_equal I18n.t("admin.sessions.locked"), flash[:alert], "the fifth in the bucket of an empty address"
    attempt(EMAIL, password: PASSWORD)
    assert_redirected_to admin_root_path
  end

  test "a closed account bucket answers the same for a known and an unknown address, and checks no password" do
    wrong_attempts(4, EMAIL)
    wrong_attempts(4, UNKNOWN)
    fifth = [ answer_to(EMAIL), answer_to(UNKNOWN) ]
    sixth = [ answer_to(EMAIL, password: PASSWORD), answer_to(UNKNOWN) ]

    assert_equal(*fifth)
    assert_equal I18n.t("admin.sessions.locked"), fifth.first[:flash]
    assert_equal [ "SignIn::Protection::LockoutMailJob" ], fifth.first[:jobs], "the pause mail's job, for an email with no account too"
    assert_equal(*sixth)
    assert_equal I18n.t("admin.sessions.locked"), sixth.first[:flash]
    assert_equal 0, sixth.first[:hashes]
    assert_empty sixth.first[:statements], "nothing is read or written"
  end

  test "the fifth failure records one session.locked with the bucket, level and seconds, and the sixth attempt in that minute records nothing" do
    wrong_attempts(4)
    assert_empty locked_events

    attempt(EMAIL)
    event = locked_events.sole
    assert_equal({ "bucket" => "account", "email_address" => EMAIL, "level" => 0, "seconds" => 60 }, event.metadata)
    assert_nil event.user_id
    assert_nil event.subject_type
    assert_equal "127.0.0.1", event.ip

    assert_no_difference -> { Audit::Event.count } do
      attempt(EMAIL)
    end
    assert_equal I18n.t("admin.sessions.locked"), flash[:alert]
  end

  test "the fifth failure enqueues one lock-out job for a known and an unknown address alike, and the next lock within the hour enqueues none" do
    [ EMAIL, UNKNOWN ].each do |email|
      wrong_attempts(4, email)
      assert_enqueued_with(job: SignIn::Protection::LockoutMailJob, args: [ email, { locked_at: Time.current, from_address: "127.0.0.1", minutes: 1, origin: "http://www.example.com" } ]) do
        attempt(email)
      end

      travel 1.minute
      assert_difference -> { locked_events.count }, 1 do
        assert_no_enqueued_jobs(only: SignIn::Protection::LockoutMailJob) { attempt(email) }
      end
      assert_equal 1, locked_events.last.metadata["level"], "the sixth failure is the next lock, two minutes"
    end
  end

  test "the fiftieth failure from an address answers Try again later and records session.locked for address_wide" do
    49.times { |index| attempt("person#{index}@example.org") }
    assert_empty locked_events

    attempt("last@example.org")
    assert_redirected_to admin_sign_in_path
    assert_equal "Try again later.", flash[:alert]
    assert_equal({ "bucket" => "address_wide", "seconds" => (1.hour - 49 * PACE).to_i }, locked_events.sole.metadata)

    assert_no_difference -> { Audit::Event.count } do
      attempt(EMAIL, password: PASSWORD)
    end
    assert_equal "Try again later.", flash[:alert]
    assert_nil cookies[:session_id]
  end

  test "behind a trusted proxy two people count in two wide buckets, and the fiftieth failure of one leaves the other signing in" do
    hop = { "REMOTE_ADDR" => "10.0.0.2" }
    50.times { |index| attempt("person#{index}@example.org", headers: { "X-Forwarded-For" => "203.0.113.1" }, env: hop) }
    assert_equal [ "203.0.113.1" ], locked_events.map(&:ip)

    attempt(EMAIL, password: PASSWORD, headers: { "X-Forwarded-For" => "203.0.113.2" }, env: hop)
    assert_redirected_to admin_root_path
    assert cookies[:session_id].present?
  end

  test "the address is counted as User normalises it: case and spaces fall into one account bucket" do
    [ " Ann@Example.ORG ", "ANN@example.org", "ann@EXAMPLE.org ", "\tann@example.org" ].each { |typed| attempt(typed) }
    assert_empty locked_events

    attempt(EMAIL)
    assert_equal I18n.t("admin.sessions.locked"), flash[:alert]
    assert_equal "account", locked_events.sole.metadata["bucket"]

    long = "#{"a" * 300}@example.org"
    5.times { attempt(long) }
    assert_equal long.first(254), locked_events.last.metadata["email_address"], "counted whole, kept cut"
  end

  test "an email that is a list or a hash is refused as any wrong address is, and counts" do
    [ [ EMAIL ], { "a" => EMAIL }, [ EMAIL ], { "b" => "x" } ].each do |junk|
      attempt(junk)
      assert_redirected_to admin_sign_in_path
      assert_equal I18n.t("admin.sessions.refused"), flash[:alert]
    end
    assert_equal [ {} ] * 4, Audit::Event.where(action: "session.failed").map(&:metadata)

    attempt([ EMAIL ])
    assert_equal I18n.t("admin.sessions.locked"), flash[:alert], "the fifth in the bucket of an empty address"
    assert_equal({ "bucket" => "account", "level" => 0, "seconds" => 60 }, locked_events.sole.metadata)
    attempt(EMAIL, password: PASSWORD)
    assert_redirected_to admin_root_path, "a typed address is another bucket"
  end

  test "the right password during a lock is refused with the same sentence, and once the lock ends it signs in and the count starts again" do
    wrong_attempts(5)
    lock_ends = Time.current - PACE + 60.seconds

    attempt(EMAIL, password: PASSWORD)
    assert_equal I18n.t("admin.sessions.locked"), flash[:alert]
    assert_nil cookies[:session_id]

    travel_to lock_ends - 1.second
    attempt(EMAIL, password: PASSWORD, paced: false)
    assert_equal I18n.t("admin.sessions.locked"), flash[:alert], "the attempt during the lock did not extend it, nor did it end early"

    travel_to lock_ends + 1.second
    attempt(EMAIL, password: PASSWORD)
    assert_redirected_to admin_root_path

    reset!
    wrong_attempts(4)
    assert_equal I18n.t("admin.sessions.refused"), flash[:alert]
    attempt(EMAIL)
    assert_equal I18n.t("admin.sessions.locked"), flash[:alert]
    assert_equal [ 0, 0 ], locked_events.map { |event| event.metadata["level"] }, "the count began again at one"
  end

  test "after three failures the next page asks for the bot check, a success forgets it, and a required check's refusal says so" do
    with_bot_check(:passed) do
      wrong_attempts(2)
      assert_nil session[:sign_in_bot_check]
      get admin_sign_in_path
      assert_nil controller.instance_variable_get(:@bot_check)

      attempt(EMAIL)
      assert_equal true, session[:sign_in_bot_check]
      get admin_sign_in_path
      assert_kind_of SignIn::Protection::BotCheck, controller.instance_variable_get(:@bot_check)

      assert_no_difference -> { Audit::Event.count } do
        attempt(EMAIL, password: PASSWORD)
      end
      assert_redirected_to admin_sign_in_path
      assert_equal I18n.t("admin.sessions.bot_check"), flash[:alert]
      assert_empty bot_check_requests, "no token, no call"

      attempt(EMAIL, password: PASSWORD, "cf-turnstile-response" => "token")
      assert_redirected_to admin_root_path
      assert_nil session[:sign_in_bot_check]
      assert_equal [ "token" ], bot_check_requests.map { |form| form["response"] }
    end
  end

  test "a bot check due by the email alone is shown through the flag, and one due by the address on any page" do
    with_bot_check(:failed) do
      wrong_attempts(3, EMAIL, headers: { "X-Forwarded-For" => "203.0.113.1" }, env: { "REMOTE_ADDR" => "10.0.0.2" })
      reset!
      get admin_sign_in_path
      assert_nil controller.instance_variable_get(:@bot_check), "another address, a fresh session"

      attempt(EMAIL, "cf-turnstile-response" => "token")
      assert_equal I18n.t("admin.sessions.bot_check"), flash[:alert]
      assert_equal true, session[:sign_in_bot_check]
      get admin_sign_in_path
      assert_kind_of SignIn::Protection::BotCheck, controller.instance_variable_get(:@bot_check)

      reset!
      get admin_sign_in_path, headers: { "X-Forwarded-For" => "203.0.113.1" }, env: { "REMOTE_ADDR" => "10.0.0.2" }
      assert_kind_of SignIn::Protection::BotCheck, controller.instance_variable_get(:@bot_check)
    end
  end

  test "the eleventh attempt in three minutes from one address is limited until the three minutes end" do
    10.times { |index| attempt("person#{index}@example.org", paced: false) }
    assert_equal I18n.t("admin.sessions.refused"), flash[:alert]

    assert_no_difference -> { Audit::Event.count } do
      attempt(EMAIL, password: PASSWORD, paced: false)
    end
    assert_redirected_to admin_sign_in_path
    assert_equal "Try again later.", flash[:alert]
    assert_nil cookies[:session_id]

    travel 3.minutes + 1.second
    attempt(EMAIL, password: PASSWORD)
    assert_redirected_to admin_root_path
  end
end
