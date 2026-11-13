require "test_helper"

# Signing in through the site's single sign-on provider, through the real
# controllers and the fake provider on 127.0.0.1 (`OidcHelper`): the start's
# redirect and its state cookie, the callback's answers, and the rule that
# keeps a person the provider owns from coming in by a passkey or a second
# step instead.
class SsoSignInTest < ActionDispatch::IntegrationTest
  include LogCapture

  STATE_COOKIE = SsoStarts::STATE_COOKIE.to_s
  # An address no fixture holds, so a sign-in by it can only accept its
  # invitation.
  EMAIL = "newcomer@example.com".freeze
  CALLBACK = "http://www.example.com/#{ContentSpiel::ADMIN_PATH}/sign-in/sso/callback".freeze

  # `complete_sign_in` called as a gem's controller calls it, through a
  # controller with no route: the concern is the hook's promise, whoever
  # includes it.
  class CompletionProbe < ActionController::Base
    include Authentication
    include Admin::SignInCompletion

    public :complete_sign_in
  end

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @exporter = Rails.application.config.x.otel_test_exporter
    @exporter.reset
  end

  # The provider's authorization address the button sends to.
  def start
    post admin_sso_path
    assert_response :see_other
    response.location
  end

  # The callback the provider sends the browser back to.
  def through_provider(idp) = idp.authorize(start)

  # The fake provider's identity is `reader@example.com` (`OidcHelper`),
  # which the `reader` fixture holds, unlinked: its first sign-in links it.

  def query_of(url) = Rack::Utils.parse_query(URI(url).query)

  # The state cookie's values, opened as the controller opens it.
  def kept_state
    jar = ActionDispatch::TestRequest.create.cookie_jar
    jar[STATE_COOKIE] = cookies[STATE_COOKIE]
    jar.encrypted[STATE_COOKIE]
  end

  def plant_state(values)
    jar = ActionDispatch::TestRequest.create.cookie_jar
    jar.encrypted[STATE_COOKIE] = { value: values }
    put_state_cookie(jar[STATE_COOKIE])
  end

  # The state cookie's raw value as a browser would send it, in place of
  # whatever the jar holds (under any path).
  def put_state_cookie(value)
    cookies.delete(STATE_COOKIE)
    cookies[STATE_COOKIE] = value
  end

  def callback_spans = @exporter.finished_spans.select { |span| span.name == "auth.sso.callback" }

  def assert_unfinished(reason, message)
    assert_redirected_to admin_sign_in_path, message
    assert_equal I18n.t("admin.sessions.sso_unfinished", provider: OidcHelper::NAME), flash[:alert], message
    assert_equal 0, Session.count, message
    span = callback_spans.last
    assert_equal [ "unfinished", reason ], span.attributes.values_at("auth.outcome", "auth.sso.reason"), message
  end

  def set_cookie_line(name) = Array(response.headers["Set-Cookie"]).flat_map { |line| line.split("\n") }.find { |line| line.start_with?("#{name}=") }

  test "the button redirects to the provider with a state cookie that is Lax, HttpOnly and pathed to the callback" do
    with_fake_idp do |idp|
      location = start

      assert location.start_with?("#{idp.issuer}/authorize?"), location
      query = query_of(location)
      assert_equal CALLBACK, query["redirect_uri"]
      assert_equal [ OidcHelper::CLIENT_ID, "code", "S256" ], query.values_at("client_id", "response_type", "code_challenge_method")

      line = set_cookie_line(STATE_COOKIE)
      assert line, "the state cookie is written"
      attributes = line.split(";").map { |part| part.strip.downcase }
      assert_includes attributes, "path=/#{ContentSpiel::ADMIN_PATH}/sign-in/sso"
      assert_includes attributes, "httponly"
      assert_includes attributes, "samesite=lax"
      assert attributes.any? { |part| part.start_with?("expires=") }, "the cookie lapses with the state"
      assert_not_includes attributes, "secure", "a plain-HTTP test site sends it without Secure"
      assert_not_includes line, query["state"], "the cookie holds the state encrypted"

      kept = kept_state
      assert_equal query.values_at("state", "nonce"), kept.values_at("state", "nonce")
      assert_equal query["code_challenge"], SignIn::Oidc::Authorization.challenge(kept["verifier"])
      assert_equal [ "sign_in", nil, Time.current.to_i ], kept.values_at("intent", "invitation_id", "at")

      redirect = @exporter.finished_spans.find { |span| span.name == "auth.sso.redirect" }
      assert_equal({ "auth.sso.intent" => "sign_in", "auth.sso.issuer_host" => "127.0.0.1" }, redirect.attributes.to_h)
    end
  end

  test "the callback signs an invited person in with the sso method, the provider token on the session, and session.created saying sso" do
    invitation = open_invitation(EMAIL)
    with_fake_idp(email: EMAIL, refresh_token: "rt-planted") do |idp|
      get through_provider(idp)

      assert_redirected_to admin_root_url
      session = Session.sole
      user = session.user
      assert_equal [ EMAIL, idp.issuer, "sub-1" ], user.values_at(:email_address, :sso_issuer, :sso_subject)
      assert_equal [ "sso", "rt-planted" ], [ session.authenticated_with, session.provider_token ]
      assert_not_nil session.provider_checked_at
      assert invitation.reload.accepted?
      event = Audit::Event.where(action: "session.created").sole
      assert_equal [ user.id, user.id ], [ event.user_id, event.subject_id ]
      assert_equal({ "method" => "sso" }, event.metadata)
      assert_empty cookies[STATE_COOKIE].to_s, "the state cookie is taken"
      assert_equal [ "ok", nil ], callback_spans.sole.attributes.values_at("auth.outcome", "auth.sso.reason")

      follow_redirect!
      assert_response :success
    end
  end

  test "an SSO session is never sent to enrolment, whatever the policy" do
    site_settings(:default).update!(passkey_policy: "everyone")
    with_fake_idp do |idp|
      get through_provider(idp)
      assert_redirected_to admin_root_url
      assert_not Session.sole.enrolment_due, "a linked person signed in by the provider"
      follow_redirect!
      assert_response :success
    end

    # The method alone exempts: an account no link exempts, signed in by sso,
    # is not due, where a password would make it so.
    person = User.create!(email_address: "plain@example.com", password: "password12345")
    probe = completion_probe
    assert probe.complete_sign_in(person, method: "sso")
    assert_not Session.find_by!(user: person, authenticated_with: "sso").enrolment_due, "an unlinked person signed in by sso"
    assert completion_probe.complete_sign_in(person, method: "password")
    assert Session.find_by!(user: person, authenticated_with: "password").enrolment_due, "the same person by password"
  end

  # A state answers once, in the browser it was given to, with its nonce,
  # within its lifetime; anything else signs nobody in.
  test "a replayed state, another browser's state, no cookie, another nonce and a late state each end unfinished with no session" do
    with_fake_idp do |idp|
      # A replay: the very answer and cookie sent again after it signed in.
      callback = through_provider(idp)
      saved = cookies[STATE_COOKIE]
      get callback
      assert_redirected_to admin_root_url
      Session.delete_all
      cookies.delete("session_id")
      token_requests = idp.requests.count { |request| request.path == "/idp/token" }
      put_state_cookie(saved)
      get callback
      assert_unfinished "bad_state", "a replayed state"
      assert_equal token_requests, idp.requests.count { |request| request.path == "/idp/token" }, "a spent state sends nothing to the provider"

      # Another browser's cookie with this browser's state.
      through_provider(idp)
      theirs = cookies[STATE_COOKIE]
      mine = through_provider(idp)
      put_state_cookie(theirs)
      get mine
      assert_unfinished "bad_state", "another browser's state"

      # No cookie at all.
      callback = through_provider(idp)
      cookies.delete(STATE_COOKIE)
      get callback
      assert_unfinished "bad_state", "no cookie"

      # A code whose ID token carries another nonce than the kept one.
      query = query_of(start)
      code = idp.code_for(nonce: "another-nonce", challenge: query["code_challenge"], redirect_uri: query["redirect_uri"])
      get admin_sso_callback_path(code: code, state: query["state"])
      assert_unfinished "bad_token", "another nonce"

      # A state older than ten minutes, its cookie still sent.
      callback = through_provider(idp)
      plant_state(kept_state.merge("at" => (Time.current - SignIn::Oidc::STATE_LIFETIME - 1.second).to_i))
      get callback
      assert_unfinished "bad_state", "a late state"
    end
  end

  test "a cancelled sign-in at the provider answers sso_unfinished and records nothing" do
    with_fake_idp do |idp|
      idp.deny!
      assert_no_difference -> { Audit::Event.count } do
        get through_provider(idp)
      end
      assert_unfinished "cancelled", "cancelled at the provider"
      assert_not idp.requests.any? { |request| request.path == "/idp/token" }
    end
  end

  test "a refused account answers sso_refused, the same sentence for no account, an unverified email and an owner" do
    sentence = I18n.t("admin.sessions.sso_refused", provider: OidcHelper::NAME)
    open_invitation("unverified@example.com")
    {
      "no_account" => { email: "stranger@example.com" },
      "email_unverified" => { email: "unverified@example.com", email_verified: false },
      "owner" => { email: users(:one).email_address }
    }.each do |reason, identity|
      with_fake_idp(**identity) do |idp|
        get through_provider(idp)
        assert_redirected_to admin_sign_in_path, reason
        assert_equal sentence, flash[:alert], reason
        assert_equal 0, Session.count, reason
        assert_equal reason, Audit::Event.where(action: "sso.refused").order(:id).last.metadata["reason"], reason
        assert_equal [ "refused", reason ], callback_spans.last.attributes.values_at("auth.outcome", "auth.sso.reason"), reason
      end
    end
    assert_not users(:one).reload.sso_linked?
  end

  test "with no provider both actions are 404" do
    with_sign_in_env(SignIn::Oidc::VARIABLES.index_with { nil }.merge("SSO_REQUIRED" => nil)) do
      post admin_sso_path
      assert_response :not_found
      get admin_sso_callback_path(code: "x", state: "y")
      assert_response :not_found
      assert_nil cookies[STATE_COOKIE]
    end
  end

  test "a provider whose discovery cannot be read is unfinished at the start, on the sign-in page" do
    with_fake_idp do |idp|
      idp.answer_discovery_with(status: 500, body: { "error" => "down" })
      post admin_sso_path
      assert_redirected_to admin_sign_in_path
      assert_equal I18n.t("admin.sessions.sso_unfinished", provider: OidcHelper::NAME), flash[:alert]
      assert_nil set_cookie_line(STATE_COOKIE), "no state is kept"
      assert_equal "500", @exporter.finished_spans.find { |span| span.name == "auth.sso.redirect" }.attributes["error.type"]
    end
  end

  test "a mismatch from an invitation's start goes to the invitation page with both addresses" do
    invitation = open_invitation("invited@example.com")
    with_fake_idp(email: "someone-else@example.com") do |idp|
      # The invitation page's own start writes this cookie: here it is planted.
      callback = through_provider(idp)
      plant_state(kept_state.merge("intent" => "invitation", "invitation_id" => invitation.id))
      get callback

      assert_redirected_to admin_invitation_path
      assert_equal({ "got" => "someone-else@example.com", "email" => "invited@example.com" }, flash[:sso_mismatch])
      assert_equal 0, Session.count
      assert_not invitation.reload.accepted?
      assert_equal [ "refused", "mismatch" ], callback_spans.sole.attributes.values_at("auth.outcome", "auth.sso.reason")
    end
  end

  test "the callback's code and state are in no exported span and no log line" do
    planted = { access: "planted-access-#{SecureRandom.hex(8)}", refresh: "planted-refresh-#{SecureRandom.hex(8)}" }
    with_fake_idp(refresh_token: planted[:refresh]) do |idp|
      @exporter.reset
      log = capture_log(LogCapture::REQUEST_LOGGERS) do
        location = start
        query = query_of(location)
        id_token = idp.id_token({ "nonce" => query["nonce"] })
        idp.answer_token_with(body: { "access_token" => planted[:access], "token_type" => "Bearer", "id_token" => id_token, "refresh_token" => planted[:refresh] })
        callback = idp.authorize(location)
        @secrets = {
          "state" => query["state"], "nonce" => query["nonce"], "code" => query_of(callback)["code"],
          "id_token" => id_token, "access_token" => planted[:access], "refresh_token" => planted[:refresh],
          "client_secret" => OidcHelper::CLIENT_SECRET
        }
        get callback
        @secrets["verifier"] = idp.requests.find { |request| request.path == "/idp/token" }.params.fetch("code_verifier")
      end

      assert_redirected_to admin_root_url
      spans = @exporter.finished_spans
      assert spans.any? { |span| span.name == "auth.sso.redirect" }
      assert spans.any? { |span| span.name == "auth.sso.callback" }
      server = spans.find { |span| span.kind == :server && span.attributes.values.any? { |value| value.to_s.include?("sign-in/sso/callback") } }
      assert_equal "[FILTERED]", server.attributes["url.query"], "the callback request's query"

      written = spans.map { |span| [ span.name, span.attributes.to_a, span.status&.description, Array(span.events).map { |event| [ event.name, event.attributes.to_a ] } ].flatten.compact.join(" ") }.join("\n")
      @secrets.each do |name, value|
        assert_not_includes written, value, "the #{name} is in no span"
        assert_not_includes log, value, "the #{name} is in no log line"
        assert_not_includes log, CGI.escape(value), "the #{name}, URL-encoded, is in no log line"
      end
      assert_match(/"code" ?=> ?"\[FILTERED\]"/, log)
      assert_match(/"state" ?=> ?"\[FILTERED\]"/, log)
    end
  end

  test "under SSO_REQUIRED a non-owner's passkey is refused as passkey_failed, and an owner's signs in" do
    member = User.create!(email_address: "member@example.org", password: "password12345")
    owner = User.create!(email_address: "owner@example.org", password: "password12345", owner: true)
    member_client = fake_authenticator
    owner_client = fake_authenticator
    add_passkey(member, client: member_client)
    add_passkey(owner, client: owner_client)

    with_sso(required: true) do
      assert_equal 1, send_sign_in_passkey(member_client, member) { |location| refused_passkey(location) }, "the refusal counts in the wide bucket"
      request_span = @exporter.finished_spans.select { |span| span.kind == :server }.last
      assert request_span.attributes["auth.refused_by_rule"], "the request's span says the rule refused it"
      assert_equal 0, Session.count, "the member is not signed in"
      assert_equal 0, Audit::Event.where(action: "session.created").count

      send_sign_in_passkey(owner_client, owner) { |location| assert_equal admin_root_url, location, "the owner signs in" }
      assert_equal [ owner ], Session.all.map(&:user)
    end

    # A linked account, whatever SSO_REQUIRED says.
    link_to_sso(member)
    Session.delete_all
    cookies.delete("session_id")
    send_sign_in_passkey(member_client, member) { |location| refused_passkey(location) }
    assert_equal 0, Session.count, "a linked account's passkey"
  end

  test "a second step held from before SSO_REQUIRED or a link is refused, by passkey and by code" do
    # SSO_REQUIRED switched on while the step was held.
    member, client, codes = member_with_second_factors("member@example.org")
    password_step(member)
    with_sso(required: true) do
      assert_equal admin_second_factor_path, second_step_passkey(client, member), "a passkey after SSO_REQUIRED"
      assert_equal I18n.t("admin.second_factor.passkey_failed"), flash[:alert], "a passkey after SSO_REQUIRED"

      post admin_second_factor_code_path, params: { recovery_code: codes.first }
      assert_redirected_to admin_second_factor_path(with: "code"), "a code after SSO_REQUIRED"
      assert_equal I18n.t("admin.second_factor.code_failed"), flash[:alert], "a code after SSO_REQUIRED"
    end
    assert_equal 0, Session.count, "nobody is signed in after SSO_REQUIRED"
    assert_equal %w[passkey recovery_code], Audit::Event.where(action: "session.second_factor_failed", subject_id: member.id).order(:id).map { |event| event.metadata["method"] },
      "each refusal after SSO_REQUIRED is audited as a wrong proof"

    # The account linked while the step was held.
    linked, client, codes = member_with_second_factors("linked@example.org")
    password_step(linked)
    link_to_sso(linked)
    post admin_second_factor_code_path, params: { recovery_code: codes.first }
    assert_redirected_to admin_second_factor_path(with: "code"), "a code after a link"
    assert_equal I18n.t("admin.second_factor.code_failed"), flash[:alert], "a code after a link"
    assert_equal admin_second_factor_path, second_step_passkey(client, linked), "a passkey after a link"
    assert_equal I18n.t("admin.second_factor.passkey_failed"), flash[:alert], "a passkey after a link"
    assert_equal 0, Session.count, "nobody is signed in after a link"
  end

  test "a recovery code refused by rule is not used, and works once SSO_REQUIRED is off" do
    member, _client, codes = member_with_second_factors("member@example.org")
    password_step(member)
    with_sso(required: true) do
      post admin_second_factor_code_path, params: { recovery_code: codes.first }
      assert_equal I18n.t("admin.second_factor.code_failed"), flash[:alert], "the refusal is a wrong code's"
    end
    assert_equal 10, member.recovery_codes.unused.count, "the refused code is still unused"
    assert_equal 0, Audit::Event.where(action: "recovery_code.used").count, "no code is recorded as used"
    step = @exporter.finished_spans.select { |span| span.name == "auth.second_factor" }.last
    assert_equal [ "refused", true ], step.attributes.values_at("auth.outcome", "auth.refused_by_rule"), "the operator sees the rule"

    post admin_second_factor_code_path, params: { recovery_code: codes.first }
    assert_redirected_to admin_account_path(anchor: "passkeys"), "the same code signs in with SSO_REQUIRED off"
    assert_equal 9, member.recovery_codes.unused.count, "and only then is it used"
  end

  test "complete_sign_in refuses an owner by an outside method and an unknown method raises" do
    owner = users(:one)
    member = User.create!(email_address: "member@example.org", password: "password12345")

    assert_no_difference -> { Session.count + Audit::Event.count } do
      assert_equal false, completion_probe.complete_sign_in(owner, method: "sso"), "an owner by sso"
    end
    error = assert_raises(ArgumentError, "an unknown method") { completion_probe.complete_sign_in(member, method: "acme/unknown") }
    assert_includes error.message, "acme/unknown"
    assert_equal 0, Session.count, "an unknown method writes nothing"

    SignInMethods.register("acme/saml", label: "acme.sign_in.saml", path: :admin_root_path)
    begin
      assert_equal false, completion_probe.complete_sign_in(owner, method: "acme/saml"), "an owner by a gem's method"
      assert_equal 0, Session.count, "an owner by a gem's method writes nothing"
      assert completion_probe.complete_sign_in(member, method: "acme/saml"), "a member by a gem's method"
    ensure
      Rails.application.reloader.prepare!
    end
    assert completion_probe.complete_sign_in(owner, method: "password"), "an owner by the password"
    assert_equal({ "acme/saml" => member.id, "password" => owner.id }, Session.pluck(:authenticated_with, :user_id).to_h)
  end

  private

  def completion_probe
    request = ActionDispatch::TestRequest.create
    request.session = ActionController::TestSession.new
    CompletionProbe.new.tap do |probe|
      probe.set_request!(request)
      probe.set_response!(ActionDispatch::TestResponse.new)
    end
  end

  # A passkey sign-in of `user`'s passkey: yields the answer's location and
  # answers the address's wide count after it.
  def send_sign_in_passkey(client, user)
    post admin_sign_in_passkey_options_path, as: :json
    challenge = response.parsed_body.fetch("challenge")
    post admin_sign_in_passkey_path, params: { credential: passkey_assertion(client, challenge: challenge, user_handle: user.webauthn_id) }, as: :json
    assert_response :success
    yield response.parsed_body.fetch("location")
    wide = VisitorAddress.key("127.0.0.1", purpose: SignIn::Throttle::KEY_PURPOSE)
    SignIn.store.read("sign_in:studio:wide:#{wide}").to_i
  end

  def refused_passkey(location)
    assert_equal admin_sign_in_path, location
    assert_equal I18n.t("admin.sessions.passkey_failed"), flash[:alert]
  end

  # A non-owner with a passkey and ten unused codes: the account, its
  # authenticator and the codes as typed.
  def member_with_second_factors(email)
    user = User.create!(email_address: email, password: "password12345")
    client = fake_authenticator
    add_passkey(user, client: client)
    codes = RecoveryCode.texts
    codes.each { |code| user.recovery_codes.create!(digest: RecoveryCode.digest(code), generated_at: Time.current) }
    [ user, client, codes ]
  end

  def password_step(user)
    post admin_sign_in_path, params: { email_address: user.email_address, password: "password12345" }
    assert_redirected_to admin_second_factor_path
  end

  def second_step_passkey(client, user)
    post admin_second_factor_options_path, as: :json
    challenge = response.parsed_body.fetch("challenge")
    post admin_second_factor_passkey_path, params: { credential: passkey_assertion(client, challenge: challenge, user_handle: user.webauthn_id) }, as: :json
    assert_response :success
    response.parsed_body.fetch("location")
  end
end
