require "test_helper"

# What sign-in's spans say, read from the in-memory exporter the test
# environment records into (`test/integration/opentelemetry_test.rb`): each
# `auth.*` span stands under the request's server span (so
# `Telemetry::WorkSampler` keeps it and none is a root of its own), and no
# span of the request, nor of a job it queued, holds what a person typed.
# The email, the password, the Turnstile token and secret are planted
# fresh in each test and searched for in every name, attribute, status
# description, link and event of every exported span, as typed, in either
# case and URL-encoded, the email's local part and domain each alone, and
# a password's SHA-1 whole, as its range prefix and as its suffix, so an
# instrumentation or an attribute that starts to write one fails here
# whatever it is called. The local part and the domain are words no
# request holds otherwise, so neither can match by chance.
class SignInTelemetryTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  # Past the per-address rate limit's pace (10 in 3 minutes), so the
  # attempts that build a lock meet only the buckets.
  PACE = 20.seconds

  setup do
    freeze_time
    site_settings(:default).update!(setup_completed_at: Time.current)
    # Typed in mixed case: the account stores it downcased, so the typed
    # form and the stored one are two searches.
    @email = "Planted.Local.#{SecureRandom.hex(6)}@Planted-Domain-#{SecureRandom.hex(6)}.test"
    @password = "planted-#{SecureRandom.hex(12)}"
    # A token and a secret carry characters a URL escapes, so their
    # encoded forms are searches of their own.
    @token = "planted-token-#{SecureRandom.hex(12)}+/="
    @user = User.create!(email_address: @email, password: @password)
    @exporter = Rails.application.config.x.otel_test_exporter
    @exporter.reset
  end

  def attempt(password: "wrong", paced: true, **params)
    post admin_sign_in_path, params: { email_address: @email, password: password, **params }
    travel PACE if paced
  end

  # The spans the block's requests (or jobs) exported, and nothing before.
  def spans_of
    @exporter.reset
    yield
    @exporter.finished_spans
  end

  # Everything a span writes that a backend stores as text: its name, its
  # attributes' keys and values, its status's description, its links'
  # attributes, and its events' names and attributes.
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

  # The one root of the spans, which every span shares the trace of.
  def request_root(spans)
    roots = spans.select { |span| root?(span) }
    assert_equal 1, roots.size, "one root: #{spans.map(&:name)}"
    assert_equal [ roots.first.trace_id ], spans.map(&:trace_id).uniq, "every span is in the root's trace"
    roots.first
  end

  def assert_under_request(spans, span)
    root = request_root(spans)
    assert_equal :server, root.kind
    assert_equal root.span_id, span.parent_span_id, "#{span.name} is a child of the request's server span"
  end

  def assert_child_of(parent, span)
    assert_equal parent.span_id, span.parent_span_id, "#{span.name} is a child of #{parent.name}"
  end

  # Every form a typed value could be written in: as typed, in either
  # case, and URL-encoded as a query or a path would carry it.
  def forms_of(value)
    [ value, value.downcase, value.upcase ].flat_map { |form| [ form, CGI.escape(form), ERB::Util.url_encode(form) ] }.uniq
  end

  # A password and every part of its SHA-1 a lookup could send or receive:
  # the whole hex, the range prefix and the suffix, each in both cases.
  def password_forms(password)
    digest = Digest::SHA1.hexdigest(password)
    [ digest, digest[0, 5], digest[5..] ].flat_map { |part| [ part, part.upcase ] }.prepend(*forms_of(password))
  end

  # `passwords:` and `secrets:` are searched beside the test's own email,
  # password and token.
  def assert_holds_nothing_typed(spans, passwords: [], secrets: [])
    assert_not_empty spans
    text = written(spans)
    local, domain = @email.split("@")
    {
      "the email" => [ @email, local, domain ].flat_map { forms_of(it) },
      "a password or a part of its SHA-1" => [ @password, *passwords ].flat_map { password_forms(it) },
      "the Turnstile token or a secret" => [ @token, *secrets ].flat_map { forms_of(it) }
    }.each do |what, values|
      values.each { |value| assert_not_includes text, value, "a span holds #{what} (#{value})" }
    end
  end

  # The three outcomes of a password sign-in, each request's spans apart:
  # a wrong password; after four more failures (the fifth closes the
  # account for a minute), an attempt in that minute; and once the minute
  # has ended, the right password.
  def three_sign_ins
    refused = spans_of { attempt }
    3.times { attempt }
    attempt # the fifth: refused, and closes the account's bucket
    locked = spans_of { attempt }
    travel 1.minute
    ok = spans_of { attempt(password: @password) }
    assert cookies["session_id"].present?, "the right password signed in"
    [ refused, locked, ok ]
  end

  test "a refused, a throttled and a successful password sign-in are auth spans under the request's server span" do
    outcomes = three_sign_ins.map do |spans|
      sign_in = named(spans, "auth.sign_in").sole
      assert_under_request(spans, sign_in)
      throttles = named(spans, "auth.throttle")
      assert_not_empty throttles
      throttles.each { |throttle| assert_child_of(sign_in, throttle) }
      assert_equal "password", sign_in.attributes["auth.method"]
      [ sign_in.attributes["auth.outcome"], throttles ]
    end

    assert_equal %w[ refused locked ok ], outcomes.map(&:first)
    locked_by = outcomes[1].last.select { |throttle| throttle.attributes["auth.tripped"] }
    assert_equal [ [ "account", true ] ], locked_by.map { |throttle| [ throttle.attributes["auth.bucket"], throttle.attributes["auth.tripped"] ] }
  end

  test "no span of those sign-ins holds the email, the password or a part of its SHA-1" do
    three_sign_ins.each { |spans| assert_holds_nothing_typed(spans) }
  end

  test "a required bot check is a CLIENT span under the sign-in and holds no token" do
    secret = "planted-secret-#{SecureRandom.hex(12)}+/="
    spans = nil
    with_bot_check(:failed) do
      with_sign_in_env("TURNSTILE_SECRET_KEY" => secret) do
        3.times { attempt }
        spans = spans_of { attempt(paced: false, "cf-turnstile-response" => @token) }
      end
    end

    assert_equal [ secret ], bot_check_requests.map { |form| form["secret"] }, "the planted secret was the one sent"
    sign_in = named(spans, "auth.sign_in").sole
    assert_under_request(spans, sign_in)
    assert_equal "bot_check_failed", sign_in.attributes["auth.outcome"]
    assert_equal true, sign_in.attributes["auth.bot_check.required"]
    bot_check = named(spans, "auth.bot_check").sole
    assert_equal :client, bot_check.kind
    assert_child_of(sign_in, bot_check)
    assert_equal "failed", bot_check.attributes["auth.bot_check.result"]

    assert_holds_nothing_typed(spans, secrets: [ secret ])
  end

  test "a leaked-password lookup on Your account is a CLIENT span under the request's and holds no part of the hash" do
    sign_in_as(@user)
    chosen = "planted-#{SecureRandom.hex(12)}"
    digest = Digest::SHA1.hexdigest(chosen)
    spans = nil
    with_leaked_password_check(leaked: [ chosen ]) do
      spans = spans_of do
        patch admin_account_password_path, params: { current_password: @password, password: chosen, password_confirmation: chosen }
      end
    end

    assert_response :unprocessable_entity
    assert_equal [ digest.upcase[0, 5] ], leaked_password_requests, "the lookup was asked for the chosen password's range"
    lookup = named(spans, "auth.leaked_password").sole
    assert_equal :client, lookup.kind
    assert_under_request(spans, lookup)
    assert_equal "leaked", lookup.attributes["auth.leaked_password.result"]

    assert_holds_nothing_typed(spans, passwords: [ chosen ])
  end

  test "a lock-out's mail is an auth.lockout_mail span under the request's, and its job's trace holds no email" do
    put_mail_state(:working)
    ActionMailer::Base.deliveries.clear
    4.times { attempt }
    fifth = spans_of { attempt }
    travel 1.minute
    sixth = spans_of { attempt } # closes the account again, within the hour's mark

    [ [ fifth, true ], [ sixth, false ] ].each do |spans, queued|
      mail = named(spans, "auth.lockout_mail").sole
      assert_under_request(spans, mail)
      assert_equal({ "auth.mail.queued" => queued }, mail.attributes.to_h)
      assert_holds_nothing_typed(spans)
    end

    job_spans = spans_of { perform_enqueued_jobs while enqueued_jobs.any? }
    assert_equal [ @email.downcase ], ActionMailer::Base.deliveries.flat_map(&:to), "the job found the account and mailed it"
    roots = job_spans.select { |span| root?(span) }
    assert_not_empty roots
    assert roots.all? { |span| span.kind == :consumer }, "each job's trace is its own: #{roots.map(&:name)}"
    assert_holds_nothing_typed(job_spans)
  end

  test "a reset request's trace, and its job's, hold no email" do
    put_mail_state(:working)
    ActionMailer::Base.deliveries.clear

    request_spans = spans_of { post admin_password_path, params: { email_address: @email } }
    request_root(request_spans)
    assert_holds_nothing_typed(request_spans)

    job_spans = spans_of { perform_enqueued_jobs while enqueued_jobs.any? }
    assert_equal [ @email.downcase ], ActionMailer::Base.deliveries.flat_map(&:to), "the job found the account and mailed it"
    assert_holds_nothing_typed(job_spans)
  end

  test "the address limit's answer is an auth.sign_in span with the address bucket" do
    10.times { attempt(paced: false) }
    spans = spans_of { attempt(paced: false) }

    assert_equal I18n.t("admin.sessions.limited"), flash[:alert]
    sign_in = named(spans, "auth.sign_in").sole
    assert_under_request(spans, sign_in)
    assert_equal({ "auth.method" => "password", "auth.outcome" => "locked" }, sign_in.attributes.to_h)
    throttle = named(spans, "auth.throttle").sole
    assert_child_of(sign_in, throttle)
    assert_equal({ "auth.bucket" => "address", "auth.tripped" => true }, throttle.attributes.to_h)
    assert_holds_nothing_typed(spans)
  end
end
