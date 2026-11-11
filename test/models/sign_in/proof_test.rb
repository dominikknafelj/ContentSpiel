require "test_helper"

# A second proof of an account whose password was already given: a
# recovery code, a passkey of the account's own, or the password again
# (Confirm it's you), each counted in the account's bucket (or the known
# device's) as the password was, on a throttle store of the test's own.
class SignIn::ProofTest < ActiveSupport::TestCase
  EMAIL = "ann@example.org".freeze
  PASSWORD = "password12345".freeze
  ADDRESS = "203.0.113.7".freeze
  Trip = SignIn::Throttle::Trip

  setup do
    freeze_time
    @user = User.create!(email_address: EMAIL, password: PASSWORD)
    @codes = RecoveryCode.texts
    @codes.each { |code| @user.recovery_codes.create!(digest: RecoveryCode.digest(code), generated_at: Time.current) }
    @store = ActiveSupport::Cache::MemoryStore.new
    @throttle = SignIn::Throttle.new(store: @store)
  end

  def proof(span: "auth.second_factor", device: nil)
    SignIn::Proof.new(account: @user, identifier: EMAIL, address: ADDRESS, device: device, span: span, throttle: @throttle)
  end

  def password_step(password: PASSWORD)
    SignIn::PasswordAttempt.new(email: EMAIL, password: password, address: ADDRESS, hostname: SignInHelper::BOT_CHECK_HOSTNAME,
      bot_check_token: nil, throttle: @throttle, bot_check: nil).call
  end

  def count_of(counter)
    digest = counter == :account ? VisitorAddress.digest(EMAIL, purpose: SignIn::Throttle::KEY_PURPOSE) : VisitorAddress.key(ADDRESS, purpose: SignIn::Throttle::KEY_PURPOSE)
    @store.read("sign_in:studio:#{counter}:#{digest}")
  end

  def spans_of(&block)
    exporter = Rails.application.config.x.otel_test_exporter
    exporter.reset
    Telemetry.tracer.in_span("test request", kind: :server, &block)
    exporter.finished_spans
  end

  def refused(trips: []) = SignIn::Outcome.new(status: :refused, account: nil, trips: trips, bot_check_due: false)

  test "a proof's failures count in the account's bucket: the fifth wrong code closes it and the right code is then refused as locked" do
    assert_equal :second_factor_required, password_step.status

    3.times { assert_equal refused, proof.recovery_code("0000-0000") }
    assert_equal refused(trips: [ Trip.new(bucket: :account, level: 0, seconds: 60) ]), proof.recovery_code("0000-0000"),
      "the password step was the first count, so the fourth wrong code is the fifth"
    assert_equal SignIn::Outcome.new(status: :locked, account: nil, trips: [ Trip.new(bucket: :account, level: 0, seconds: 60) ], bot_check_due: false),
      proof.recovery_code(@codes.first)
    assert_equal 10, @user.recovery_codes.unused.count, "a locked proof checks nothing, and the right code stays unused"
    assert_equal :locked, proof.password(PASSWORD).status
    assert_equal :locked, password_step.status, "the password step meets the same lock"
  end

  test "a used code and a wrong code are the same refusal" do
    assert proof.recovery_code(@codes.first).ok?

    used = wrong = nil
    used_spans = spans_of { used = proof.recovery_code(@codes.first) }
    wrong_spans = spans_of { wrong = proof.recovery_code("ZZZZ-ZZZZ") }

    assert_equal refused, used
    assert_equal used, wrong
    assert_equal refused, proof.recovery_code([ @codes.second ]), "a list is a wrong code"
    assert_equal refused, proof.recovery_code(nil)
    said = ->(spans) { spans.reject { |span| span.name == "test request" }.map { |span| [ span.name, span.attributes.to_h ] } }
    assert_equal said.(used_spans), said.(wrong_spans), "the spans say the same of both"
  end

  test "a right proof clears the run the password step began" do
    password_step(password: "wrong")
    assert_equal :second_factor_required, password_step.status
    assert_equal 2, count_of(:account)

    outcome = nil
    spans = spans_of { outcome = proof.recovery_code(@codes.first.downcase.delete("-")) }

    assert_equal SignIn::Outcome.new(status: :ok, account: @user, trips: [], bot_check_due: false), outcome
    assert_nil count_of(:account), "the run is forgotten"
    assert_equal 1, count_of(:wide), "the proof took its own address count back; the wrong password's stands"
    assert_equal 9, @user.recovery_codes.unused.count
    second_factor = spans.find { |span| span.name == "auth.second_factor" }
    assert_equal({ "auth.method" => "recovery_code", "auth.outcome" => "ok" }, second_factor.attributes.to_h)
    code_span = spans.find { |span| span.name == "auth.recovery_code" }
    assert_equal({ "auth.outcome" => "ok" }, code_span.attributes.to_h)
    assert_equal second_factor.span_id, code_span.parent_span_id
  end

  test "the password again proves the account, and a wrong one or a list counts as a refusal" do
    assert_equal refused, proof(span: "auth.confirmation").password("wrong")
    assert_equal refused, proof(span: "auth.confirmation").password([ PASSWORD ])
    assert_equal 2, count_of(:account)

    outcome = nil
    spans = spans_of { outcome = proof(span: "auth.confirmation").password(PASSWORD) }
    assert outcome.ok?
    assert_nil count_of(:account)
    assert_equal({ "auth.method" => "password", "auth.outcome" => "ok" }, spans.find { |span| span.name == "auth.confirmation" }.attributes.to_h)
  end

  test "from a known device the proof counts in the device's bucket and the account's lock does not refuse it" do
    5.times { password_step(password: "wrong") }
    assert_equal :locked, password_step.status
    device = SignIn::KnownDevice.new.remember(EMAIL)

    assert_equal refused, proof(device: device).recovery_code("0000-0000")
    assert_equal 5, count_of(:account), "the device's failure is not the account's"
    assert proof(device: device).recovery_code(@codes.first).ok?
    assert_equal :locked, proof.recovery_code(@codes.second).status, "the account's lock stands for any other browser"
    assert_equal :locked, proof(device: SignIn::KnownDevice.new).recovery_code(@codes.second).status, "a device that does not know the account is the account's"
  end

  test "a passkey proof finds only the account's own passkeys" do
    client = fake_authenticator
    check = SignIn::PasskeyCheck.new(relying_party: passkey_relying_party(client))
    other = users(:author)
    add_passkey(other, client: client)

    _json, challenge = check.options
    stranger = proof.passkey(passkey_assertion(client, challenge: challenge, user_handle: other.webauthn_handle!), challenge: challenge, check: check, ceremony: "second_factor")
    assert_equal refused, stranger
    assert_equal 1, count_of(:account)

    mine = fake_authenticator
    add_passkey(@user, client: mine)
    _json, challenge = check.options
    outcome = nil
    spans = spans_of do
      outcome = proof.passkey(passkey_assertion(mine, challenge: challenge, user_handle: @user.webauthn_handle!), challenge: challenge, check: check, ceremony: "second_factor")
    end

    assert_equal SignIn::Outcome.new(status: :ok, account: @user, trips: [], bot_check_due: false), outcome
    assert_nil count_of(:account)
    second_factor = spans.find { |span| span.name == "auth.second_factor" }
    assert_equal({ "auth.method" => "passkey", "auth.outcome" => "ok" }, second_factor.attributes.to_h)
    assert_equal second_factor.span_id, spans.find { |span| span.name == "auth.passkey" }.parent_span_id
  end

  test "no span of a proof holds the email, the password, the code or the credential" do
    email = "Planted.#{SecureRandom.hex(6)}@Planted-#{SecureRandom.hex(6)}.test"
    password = "planted-#{SecureRandom.hex(12)}"
    @user = User.create!(email_address: email, password: password)
    code = RecoveryCode.texts.first
    @user.recovery_codes.create!(digest: RecoveryCode.digest(code), generated_at: Time.current)
    client = fake_authenticator
    check = SignIn::PasskeyCheck.new(relying_party: passkey_relying_party(client))
    passkey = add_passkey(@user, client: client)
    _json, challenge = check.options
    credential = passkey_assertion(client, challenge: challenge, user_handle: @user.webauthn_handle!)
    proof = ->(span) { SignIn::Proof.new(account: @user, identifier: email.downcase, address: ADDRESS, span: span, throttle: @throttle) }

    spans = spans_of do
      proof.("auth.second_factor").recovery_code(code.sub("-", "-x"))
      proof.("auth.second_factor").recovery_code(code)
      proof.("auth.confirmation").password(password.reverse)
      proof.("auth.confirmation").password(password)
      assert proof.("auth.second_factor").passkey(credential, challenge: challenge, check: check, ceremony: "second_factor").ok?
    end

    written = spans.map do |span|
      [ span.name, span.attributes.to_a, span.status&.description, Array(span.events).map { |event| [ event.name, event.attributes.to_a ] } ].flatten.compact.join(" ")
    end.join("\n")
    [ email, email.downcase, password, password.reverse, code, code.delete("-"), challenge, passkey.external_id, passkey.public_key, @user.webauthn_handle! ].each do |secret|
      assert_not_includes written.downcase, secret.downcase
    end
    assert_equal 5, spans.count { |span| SignIn::Proof::SPANS.include?(span.name) }
  end

  test "a span that is neither step is refused" do
    assert_raises(ArgumentError) { proof(span: "auth.sign_in") }
  end
end
