require "test_helper"

# What the passkey and recovery-code spans say, read from the in-memory
# exporter the test environment records into (`test/integration/
# opentelemetry_test.rb`), in the pattern of `sign_in_telemetry_test.rb`:
# each new `auth.*` span stands under the request's server span (so
# `Telemetry::WorkSampler` keeps it and none is a root of its own), writes
# only the keys `Telemetry::ATTRIBUTES` lists, each with one of its listed
# words, and no span of the request, nor of a job it queued, holds what a
# person typed or what a ceremony carries. The email, the password, the
# recovery codes, the passkey's name, its credential id and public key, a
# refused stranger's credential id, and every challenge the options
# answered are planted or kept fresh in each test and searched for in every
# name, attribute, status description, link and event of every exported
# span (the password step's own request too), as typed, in either case and
# URL-encoded.
class PasskeyTelemetryTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  # Past the per-address rate limits' pace (10 in 3 minutes), so a run of
  # attempts meets only the throttle's buckets, and well inside the second
  # step's five minutes.
  PACE = 20.seconds

  # The words each key these spans write may carry. A key outside
  # `Telemetry::ATTRIBUTES` fails whatever it carries; a listed key of PR 1's
  # spans that is not here (a level, a count) is held to the list alone.
  WORDS = {
    "auth.method" => %w[password passkey recovery_code],
    "auth.outcome" => SignIn::OUTCOMES.map(&:to_s),
    "auth.passkey.ceremony" => [ "register", *SignIn::PasskeyCheck::CEREMONIES ],
    "auth.mail.kind" => SignInMailer::ACCOUNT_MAILS.map(&:to_s),
    "auth.mail.queued" => [ true, false ],
    "auth.policy" => SiteSetting::PASSKEY_POLICIES,
    "auth.second_factor.required" => [ true ],
    "auth.bucket" => %w[account address address_wide device],
    "auth.tripped" => [ true, false ]
  }.freeze

  setup do
    freeze_time
    site_settings(:default).update!(setup_completed_at: Time.current)
    put_mail_state(:working)
    @email = "Planted.Local.#{SecureRandom.hex(6)}@Planted-Domain-#{SecureRandom.hex(6)}.test"
    @password = "planted-#{SecureRandom.hex(12)}"
    @name = "Planted Key #{SecureRandom.hex(6)}"
    @user = User.create!(email_address: @email, password: @password)
    @client = fake_authenticator
    @challenges = []
    @stranger_ids = []
    @exporter = Rails.application.config.x.otel_test_exporter
    @exporter.reset
  end

  def with_passkey
    @passkey = add_passkey(@user, client: @client, name: @name)
  end

  def with_codes
    @codes = RecoveryCode.texts
    @codes.each { |code| @user.recovery_codes.create!(digest: RecoveryCode.digest(code), generated_at: Time.current) }
  end

  # The spans the block's requests (or jobs) exported, and nothing before.
  def spans_of
    @exporter.reset
    yield
    @exporter.finished_spans
  end

  def written(spans)
    spans.map do |span|
      [
        span.name, span.attributes.to_a, span.status&.description,
        Array(span.links).map { |link| link.attributes.to_a },
        Array(span.events).map { |event| [ event.name, event.attributes.to_a ] }
      ].flatten.compact.join(" ")
    end.join("\n")
  end

  def root?(span) = span.parent_span_id == OpenTelemetry::Trace::INVALID_SPAN_ID

  def named(spans, name) = spans.select { |span| span.name == name }

  def request_root(spans)
    roots = spans.select { |span| root?(span) }
    assert_equal 1, roots.size, "one root: #{spans.map(&:name)}"
    assert_equal [ roots.first.trace_id ], spans.map(&:trace_id).uniq, "every span is in the root's trace"
    assert_equal :server, roots.first.kind
    roots.first
  end

  def assert_under_request(spans, span)
    assert_equal request_root(spans).span_id, span.parent_span_id, "#{span.name} is a child of the request's server span"
  end

  def assert_child_of(parent, span)
    assert_equal parent.span_id, span.parent_span_id, "#{span.name} is a child of #{parent.name}"
  end

  # Every `auth.*` span, and the request's own `auth.*` keys, write listed
  # keys with listed words only.
  def assert_listed_words(spans)
    spans.each do |span|
      attributes = span.attributes.to_h
      attributes = attributes.select { |key, _| key.start_with?("auth.") } unless span.name.start_with?("auth.")
      attributes.each do |key, value|
        assert_includes Telemetry::ATTRIBUTES, key, "#{span.name} writes an unlisted key"
        assert_includes WORDS[key], value, "#{span.name}'s #{key} is an unlisted word" if WORDS.key?(key)
      end
    end
  end

  def forms_of(value)
    [ value, value.downcase, value.upcase ].flat_map { |form| [ form, CGI.escape(form), ERB::Util.url_encode(form) ] }.uniq
  end

  def assert_holds_nothing_secret(spans)
    assert_not_empty spans
    text = written(spans)
    local, domain = @email.split("@")
    {
      "the email" => [ @email, local, domain ],
      "the password" => [ @password ],
      "a recovery code" => Array(@codes).flat_map { |code| [ code, code.delete("-") ] },
      "the passkey's name" => [ @name ],
      "the credential id or public key" => @user.passkeys.reload.flat_map { |passkey| [ passkey.external_id, passkey.public_key ] },
      "a refused credential's id" => @stranger_ids,
      "a challenge" => @challenges
    }.each do |what, values|
      values.flat_map { forms_of(it) }.each { |value| assert_not_includes text, value, "a span holds #{what} (#{value})" }
    end
  end

  # Each challenge an options answer hands out is kept, to be searched for.
  def challenge_from(path)
    post path, as: :json
    assert_response :success
    response.parsed_body.fetch("challenge").tap { |challenge| @challenges << challenge }
  end

  def assertion(challenge, client: @client)
    passkey_assertion(client, challenge: challenge, user_handle: @user.webauthn_id)
  end

  def passkey_sign_in(credential)
    post admin_sign_in_passkey_path, params: { credential: credential }, as: :json
    assert_response :success
    travel PACE
  end

  def password_step
    post admin_sign_in_path, params: { email_address: @email, password: @password }
    assert_redirected_to(/second-step/)
    travel PACE
  end

  def send_code(code)
    post admin_second_factor_code_path, params: { recovery_code: code }
    travel PACE
  end

  # A passkey sign-in refused (a credential the authenticator made but the
  # site never stored) and one accepted, each request's spans apart.
  def passkey_sign_ins
    stranger = fake_authenticator
    @stranger_ids << passkey_registration(@user, client: stranger).external_id
    challenge = challenge_from(admin_sign_in_passkey_options_path)
    credential = assertion(challenge, client: stranger)
    assert_equal @stranger_ids, [ JSON.parse(credential).fetch("id") ], "the id the refused answer carries is planted"
    refused = spans_of { passkey_sign_in(credential) }
    challenge = challenge_from(admin_sign_in_passkey_options_path)
    ok = spans_of { passkey_sign_in(assertion(challenge)) }
    assert_equal "passkey", Session.sole.authenticated_with
    [ refused, ok ]
  end

  # The second step by code (the password step's spans kept in
  # @password_spans): a wrong one; after three more (the password's
  # count and four codes close the account for a minute), an attempt in that
  # minute; and once the minute has ended, a right one.
  def code_steps
    @password_spans = spans_of { password_step }
    wrong = spans_of { send_code("0000-0000") }
    3.times { send_code("0000-0000") }
    locked = spans_of { send_code(@codes.first) }
    travel 1.minute
    right = spans_of { send_code(@codes.first) }
    assert_equal "recovery_code", Session.sole.authenticated_with
    [ wrong, locked, right ]
  end

  def wrong_confirmation
    sign_in_as(@user)
    travel Session::CONFIRM_WINDOW + 1.minute
    spans_of { post admin_account_confirmation_path, params: { password: "wrong-#{SecureRandom.hex(4)}" }, as: :json }.tap do
      assert_response :unprocessable_entity
    end
  end

  test "a passkey sign-in, refused and accepted, exports auth.passkey under auth.sign_in's request with only listed words" do
    with_passkey
    refused, ok = passkey_sign_ins

    [ [ refused, "refused" ], [ ok, "ok" ] ].each do |spans, outcome|
      passkey = named(spans, "auth.passkey").sole
      assert_under_request(spans, passkey)
      assert_equal({ "auth.passkey.ceremony" => "sign_in", "auth.outcome" => outcome }, passkey.attributes.to_h)
      assert_empty named(spans, "auth.sign_in"), "a passkey sign-in has no password attempt"
      assert_listed_words(spans)
    end
    assert_equal "nobody", request_root(ok).attributes["auth.policy"], "the policy a session was started under is on the request's span"
    assert_nil request_root(refused).attributes["auth.policy"], "a refusal starts no session"
  end

  test "the second step by code, wrong, right and locked, exports auth.second_factor and auth.recovery_code with only listed words" do
    with_passkey
    with_codes
    password_spans = spans_of { password_step }
    sign_in = named(password_spans, "auth.sign_in").sole
    assert_equal({ "auth.method" => "password", "auth.account_exists" => true, "auth.outcome" => "second_factor_required",
      "auth.second_factor.required" => true }, sign_in.attributes.to_h)
    assert_nil request_root(password_spans).attributes["auth.policy"], "the password step starts no session"

    outcomes = code_steps.map do |spans|
      step = named(spans, "auth.second_factor").sole
      assert_under_request(spans, step)
      assert_equal "recovery_code", step.attributes["auth.method"]
      named(spans, "auth.recovery_code").each { |code| assert_child_of(step, code) }
      assert_listed_words(spans)
      [ step.attributes["auth.outcome"], named(spans, "auth.recovery_code").map { |code| code.attributes["auth.outcome"] } ]
    end

    assert_equal [ [ "refused", [ "refused" ] ], [ "locked", [] ], [ "ok", [ "ok" ] ] ], outcomes,
      "a locked step checks no code"
  end

  test "a right code's mail is an auth.account_mail span under the request's, with the policy beside it" do
    with_codes
    password_step
    spans = spans_of { send_code(@codes.first) }

    mail = named(spans, "auth.account_mail").sole
    assert_under_request(spans, mail)
    assert_equal({ "auth.mail.kind" => "recovery_code_used", "auth.mail.queued" => true }, mail.attributes.to_h)
    assert_equal "nobody", request_root(spans).attributes["auth.policy"]
    assert_listed_words(spans)
  end

  test "a refused confirmation exports auth.confirmation" do
    spans = wrong_confirmation

    confirmation = named(spans, "auth.confirmation").sole
    assert_under_request(spans, confirmation)
    assert_equal({ "auth.method" => "password", "auth.outcome" => "refused" }, confirmation.attributes.to_h)
    assert_listed_words(spans)
  end

  test "no span or event holds the email, the password, the code typed, the credential id, the challenge or the passkey's name" do
    traces = []

    with_passkey
    with_codes
    traces.concat(passkey_sign_ins)
    delete admin_sign_out_path
    traces.concat(code_steps)
    traces << @password_spans
    delete admin_sign_out_path

    traces << spans_of { password_step }
    challenge = challenge_from(admin_second_factor_options_path)
    traces << spans_of do
      post admin_second_factor_passkey_path, params: { credential: assertion(challenge) }, as: :json
    end
    assert_equal admin_root_url, response.parsed_body.fetch("location"), "the second step's passkey signed in"
    delete admin_sign_out_path

    traces << wrong_confirmation
    challenge = challenge_from(admin_account_confirmation_options_path)
    traces << spans_of do
      post admin_account_confirmation_passkey_path, params: { credential: assertion(challenge) }, as: :json
    end
    assert_response :ok

    # A second passkey added on Your account: the registration ceremony, and
    # its mail, which carries the typed name to the job.
    other = fake_authenticator
    challenge = challenge_from(admin_account_passkey_options_path)
    traces << spans_of do
      credential = other.create(challenge: challenge, rp_id: passkey_relying_party(other).id, user_verified: true).to_json
      post admin_account_passkeys_path, params: { credential: credential, name: @name }.to_json,
        headers: { "Content-Type" => "application/json", "Accept" => "text/vnd.turbo-stream.html, application/json" }
    end
    assert_equal 2, @user.passkeys.count, "the second passkey was added"
    register = traces.last.find { |span| span.name == "auth.passkey" && span.attributes["auth.passkey.ceremony"] == "register" }
    assert_equal "ok", register&.attributes&.dig("auth.outcome")

    traces << spans_of { perform_enqueued_jobs while enqueued_jobs.any? }
    assert_not_empty ActionMailer::Base.deliveries, "the jobs mailed"

    traces.each do |spans|
      assert_holds_nothing_secret(spans)
      assert_listed_words(spans)
    end
  end
end
