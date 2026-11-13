require "test_helper"

# What single sign-on's spans say, read from the in-memory exporter the test
# environment records into (`test/integration/opentelemetry_test.rb`), in the
# pattern of `sign_in_telemetry_test.rb` and `passkey_telemetry_test.rb`:
#
# - the start's `auth.sso.redirect` and the callback's `auth.sso.callback`
#   stand under the request's server span, and the provider's CLIENT spans
#   (`auth.sso.discovery`, `auth.sso.token`) under them, so
#   `Telemetry::WorkSampler` keeps them and none is a root of its own;
# - the re-check's `auth.sso.recheck_run` stands under the job's CONSUMER
#   span, with one CLIENT `auth.sso.recheck` under it per session asked;
# - every key those spans write is in `Telemetry::ATTRIBUTES`, and each key
#   WORDS names carries one of its words; `auth.sso.reason` carries each
#   span's own (SPAN_WORDS): the callback's `SignIn::Oidc::SPAN_REASONS`,
#   discovery's `DISCOVERY_REASONS` or an `http_<status>`, the re-check's
#   `RECHECK_REASONS`;
# - no span or event holds the code, the state, the nonce, the PKCE
#   verifier, the ID, access or refresh token, the client secret or the email
#   the provider gave. They are planted through the fake provider
#   (`OidcHelper`) and searched for in every name, attribute, status
#   description, link and event of every exported span, as sent, in either
#   case and URL-encoded, the email's local part and domain each alone.
#
# So a change that moves a span out of its parent, writes a word outside its
# span's set or leaks a value fails here, whichever file made it.
class SsoTelemetryTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  # The words each key the SSO spans write may carry, beside a span's own
  # (SPAN_WORDS). A listed key that is not here (a count) is held to
  # `Telemetry::ATTRIBUTES` alone.
  WORDS = {
    "auth.outcome" => SignIn::OUTCOMES.map(&:to_s),
    "auth.sso.intent" => SsoStarts::INTENTS,
    "auth.sso.cached" => [ true, false ],
    "auth.sso.refresh_token" => [ true, false ],
    "auth.sso.issuer_host" => [ "127.0.0.1" ],
    "server.address" => [ "127.0.0.1" ],
    "auth.method" => %w[sso]
  }.freeze

  # A key whose words depend on the span: the callback's reason is a
  # sign-in's, discovery's System status's, the re-check's an answer's. A
  # callable is asked of the value.
  SPAN_WORDS = {
    "auth.sso.callback" => { "auth.sso.reason" => SignIn::Oidc::SPAN_REASONS },
    "auth.sso.discovery" => { "auth.sso.reason" => SignIn::Oidc.method(:discovery_reason?) },
    "auth.sso.recheck" => { "auth.sso.reason" => SignIn::Oidc::RECHECK_REASONS }
  }.freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    # Words no request holds otherwise, so none can match by chance.
    @email = "Planted.Local.#{SecureRandom.hex(6)}@Planted-Domain-#{SecureRandom.hex(6)}.test"
    @exporter = Rails.application.config.x.otel_test_exporter
    @exporter.reset
  end

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

  def sole_root(spans, kind)
    roots = spans.select { |span| root?(span) }
    assert_equal 1, roots.size, "one root: #{spans.map(&:name)}"
    assert_equal [ roots.first.trace_id ], spans.map(&:trace_id).uniq, "every span is in the root's trace"
    assert_equal kind, roots.first.kind
    roots.first
  end

  def assert_under_request(spans, span)
    assert_equal sole_root(spans, :server).span_id, span.parent_span_id, "#{span.name} is a child of the request's server span"
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
      words = WORDS.merge(SPAN_WORDS.fetch(span.name, {}))
      attributes.each do |key, value|
        assert_includes Telemetry::ATTRIBUTES, key, "#{span.name} writes an unlisted key"
        next unless words.key?(key)

        listed = words[key].respond_to?(:call) ? words[key].call(value) : words[key].include?(value)
        assert listed, "#{span.name}'s #{key} is an unlisted word (#{value.inspect})"
      end
    end
  end

  def forms_of(value)
    [ value, value.downcase, value.upcase ].flat_map { |form| [ form, CGI.escape(form), ERB::Util.url_encode(form) ] }.uniq
  end

  def assert_holds_none(spans, secrets)
    assert_not_empty spans
    text = written(spans)
    secrets.each do |what, values|
      Array(values).flat_map { forms_of(it) }.each { |value| assert_not_includes text, value, "a span holds #{what} (#{value})" }
    end
  end

  def query_of(url) = Rack::Utils.parse_query(URI(url).query)

  # The start's spans and the provider's authorization address.
  def start
    location = nil
    spans = spans_of do
      post admin_sso_path
      assert_response :see_other
      location = response.location
    end
    [ spans, location ]
  end

  # The start, the provider's redirect and the callback: each request's
  # spans apart. `cookie: false` drops the state cookie before the callback.
  def round_trip(idp, cookie: true)
    started, location = start
    callback = idp.authorize(location)
    cookies.delete(SsoStarts::STATE_COOKIE.to_s) unless cookie
    called = spans_of { get callback }
    [ started, called ]
  end

  # A start the provider's discovery refused: its spans, on the sign-in page.
  def start_refused
    spans = spans_of do
      post admin_sso_path
      assert_redirected_to admin_sign_in_path
    end
    spans
  end

  def assert_redirect_span(spans)
    redirect = named(spans, "auth.sso.redirect").sole
    assert_under_request(spans, redirect)
    named(spans, "auth.sso.discovery").each { |discovery| assert_child_of(redirect, discovery) }
    assert_listed_words(spans)
  end

  def callback_span(spans)
    callback = named(spans, "auth.sso.callback").sole
    assert_under_request(spans, callback)
    assert_listed_words(spans)
    callback
  end

  test "an SSO sign-in, refused, unfinished and accepted, exports auth.sso.redirect, auth.sso.callback and auth.sso.token under the request with only listed words" do
    open_invitation("invited@example.com")
    with_fake_idp(email: "stranger@example.com", subject: "sub-stranger") do |idp|
      # A provider whose discovery answers 500: the start is unfinished, and
      # discovery's span says why in its own words.
      idp.answer_discovery_with(status: 500, body: { "error" => "down" })
      started = start_refused
      assert_redirect_span(started)
      discovery = named(started, "auth.sso.discovery").sole
      assert_equal [ "http_500", "500" ], discovery.attributes.values_at("auth.sso.reason", "error.type")

      outcomes = []

      started, called = round_trip(idp)
      assert_redirect_span(started)
      callback = callback_span(called)
      token = named(called, "auth.sso.token").sole
      assert_equal :client, token.kind
      assert_child_of(callback, token)
      outcomes << callback.attributes.values_at("auth.outcome", "auth.sso.reason")

      started, called = round_trip(idp, cookie: false)
      assert_redirect_span(started)
      callback = callback_span(called)
      assert_empty named(called, "auth.sso.token"), "a bad state sends nothing to the provider"
      outcomes << callback.attributes.values_at("auth.outcome", "auth.sso.reason")

      idp.change_identity(subject: "sub-invited", email: "invited@example.com")
      started, called = round_trip(idp)
      assert_redirect_span(started)
      callback = callback_span(called)
      token = named(called, "auth.sso.token").sole
      assert_child_of(callback, token)
      assert_equal [ "127.0.0.1", true ], token.attributes.values_at("server.address", "auth.sso.refresh_token")
      outcomes << callback.attributes.values_at("auth.outcome", "auth.sso.reason")

      assert_equal [ [ "refused", "no_account" ], [ "unfinished", "bad_state" ], [ "ok", nil ] ], outcomes
      assert_equal "sso", Session.sole.authenticated_with
    end
  end

  test "the re-check job exports auth.sso.recheck_run with a CLIENT auth.sso.recheck per session" do
    user = link_to_sso(users(:reader), subject: "sub-1")
    with_fake_idp(refresh_token: "rt-1") do |idp|
      2.times { Session.start(user: user, method: "sso", user_agent: nil, ip_address: nil, provider_token: "rt-1") }

      run = lambda do
        travel Session::PROVIDER_CHECK_EVERY + 1.minute
        Session.update_all(last_seen_at: Time.current) # version: none (a test's own rows)
        spans_of { Sso::RecheckJob.perform_now }
      end

      answered = [ [ run.call, "ok", 0 ] ]
      idp.revoke!
      answered << [ run.call, "revoked", 2 ]
      answered.each do |spans, outcome, ended|
        job = sole_root(spans, :consumer)
        recheck_run = named(spans, "auth.sso.recheck_run").sole
        assert_child_of(job, recheck_run)
        rechecks = named(spans, "auth.sso.recheck")
        assert_equal 2, rechecks.size, "one per session"
        rechecks.each do |recheck|
          assert_equal :client, recheck.kind
          assert_child_of(recheck_run, recheck)
          assert_equal outcome, recheck.attributes["auth.outcome"]
        end
        assert_equal 2, recheck_run.attributes["auth.sso.recheck.checked"]
        assert_equal 2, recheck_run.attributes["auth.sso.recheck.#{outcome}"]
        assert_equal ended, recheck_run.attributes["auth.session.count"]
        assert_listed_words(spans)
      end
      assert_equal 0, Session.count

      # An answer that comes but cannot be used: an ID token signed by a key
      # the provider never serves is `bad_token`, the session left for later.
      Session.start(user: user, method: "sso", user_agent: nil, ip_address: nil, provider_token: "rt-1")
      idp.answer_token_with(body: { "access_token" => "at-1", "token_type" => "Bearer", "id_token" => idp.id_token({}, key: :unknown) })
      spans = run.call
      recheck = named(spans, "auth.sso.recheck").sole
      assert_equal [ "unavailable", "bad_token" ], recheck.attributes.values_at("auth.outcome", "auth.sso.reason")
      assert_equal 1, named(spans, "auth.sso.recheck_run").sole.attributes["auth.sso.recheck.unavailable"]
      assert_listed_words(spans)
      assert_equal 1, Session.count
    end
  end

  test "no span or event holds the code, the state, the nonce, the verifier, an ID, access or refresh token, the client secret or the provider's email" do
    open_invitation(@email.downcase)
    access = "planted-access-#{SecureRandom.hex(8)}+/="
    refresh = "planted-refresh-#{SecureRandom.hex(8)}+/="
    rotated = "planted-rotated-#{SecureRandom.hex(8)}+/="
    with_fake_idp(email: @email, subject: "sub-planted-#{SecureRandom.hex(6)}", refresh_token: refresh) do |idp|
      # Refused first: another verified address the provider gave, which
      # only `sso.refused`'s metadata may keep.
      stranger = "Stranger.#{SecureRandom.hex(6)}@Elsewhere-#{SecureRandom.hex(6)}.test"
      idp.change_identity(subject: "sub-stranger-#{SecureRandom.hex(6)}", email: stranger)
      refused = round_trip(idp).flatten
      idp.change_identity(subject: "sub-planted", email: @email)

      started, location = start
      query = query_of(location)
      id_token = idp.id_token({ "nonce" => query["nonce"] })
      idp.answer_token_with(body: { "access_token" => access, "token_type" => "Bearer", "id_token" => id_token, "refresh_token" => refresh })
      callback = idp.authorize(location)
      called = spans_of { get callback }
      assert_redirected_to admin_root_url
      verifier = idp.requests.select { |request| request.path == "/idp/token" }.last.params.fetch("code_verifier")
      jobs = spans_of { perform_enqueued_jobs while enqueued_jobs.any? }

      # The re-check sends the refresh token and is answered a rotated one,
      # with a fresh ID token naming the same email.
      idp.rotate_refresh_token(rotated)
      travel Session::PROVIDER_CHECK_EVERY + 1.minute
      Session.update_all(last_seen_at: Time.current) # version: none (a test's own rows)
      recheck = spans_of { Sso::RecheckJob.perform_now }
      assert_equal rotated, Session.sole.provider_token, "the re-check was answered"

      local, domain = @email.split("@")
      stranger_local, stranger_domain = stranger.split("@")
      assert_holds_none(refused + started + called + jobs + recheck,
        "the state" => query["state"], "the nonce" => query["nonce"], "the code" => query_of(callback)["code"],
        "the verifier" => verifier, "the ID token" => id_token, "the access token" => access,
        "a refresh token" => [ refresh, rotated ], "the client secret" => OidcHelper::CLIENT_SECRET,
        "the provider's email" => [ @email, local, domain, stranger, stranger_local, stranger_domain ])
    end
  end
end
