require "test_helper"

class SessionsTest < ActionDispatch::IntegrationTest
  include ActionCable::TestHelper

  setup do
    @user = User.create!(email_address: "admin@example.com", password: "password12345")
  end

  test "the session cookie expires with the session" do
    freeze_time do
      post admin_sign_in_url, params: { email_address: "admin@example.com", password: "password12345" }

      header = Array(response.headers["Set-Cookie"]).join("\n").lines.find { |line| line.start_with?("session_id=") }
      expires = Time.httpdate(header[/expires=([^;]+)/i, 1])
      assert_in_delta 14.days.from_now.to_f, expires.to_f, 60
    end
  end

  # The only reason anyone signs in at all is to reach CS Studio -- the public
  # site needs no authentication of its own, so a "cold" sign-in (one that
  # didn't arrive here via `request_authentication` redirecting from some
  # other protected page, which is the only thing that ever records a
  # return_to_after_authenticating) has nothing more useful to send the
  # visitor back to than the admin itself.
  test "signing in with no page to return to redirects to CS Studio" do
    post admin_sign_in_url, params: { email_address: "admin@example.com", password: "password12345" }

    assert_redirected_to admin_root_path
  end

  # The normal case: signing in *because* a protected page demanded it sends
  # the visitor on to the page they actually asked for, not just the admin
  # root.
  test "signing in after being redirected from a protected page returns there" do
    get "/cs-studio/settings"
    assert_redirected_to "/cs-studio/sign-in"

    post "/cs-studio/sign-in", params: { email_address: "admin@example.com", password: "password12345" }

    assert_redirected_to "/cs-studio/settings"
  end

  test "signing in with invalid credentials redirects back to the sign-in form" do
    post admin_sign_in_url, params: { email_address: "admin@example.com", password: "wrong" }

    assert_redirected_to admin_sign_in_url
  end

  # Access-control design spec §4.3 "Sessions" and Review Focus 5: a
  # failed sign-in names the email that was tried and no user, and nothing
  # of the password -- not under any key, not as a value.
  test "a failed sign-in records session.failed with the email and no password" do
    post admin_sign_in_url, params: { email_address: "admin@example.com", password: "wrong-secret" }

    event = Audit::Event.find_by!(action: "session.failed")
    assert_equal({ "email_address" => "admin@example.com" }, event.metadata)
    assert_nil event.user_id
    assert_nil event.actor
    assert_equal "admin", event.channel
    assert_not_includes event.attributes.to_json, "wrong-secret"
    assert_not_includes event.metadata.keys.join, "passw"
  end

  # Final fix wave (Minor 4): a password typed into the email box (no "@")
  # isn't stored at all, and a long value is cut to an address's length.
  test "a failed sign-in stores no email that isn't one, and truncates a long one" do
    post admin_sign_in_url, params: { email_address: "hunter2-my-password", password: "x" }
    assert_equal({}, Audit::Event.find_by!(action: "session.failed").metadata)
    assert_not_includes Audit::Event.find_by!(action: "session.failed").attributes.to_json, "hunter2"

    long = "#{"a" * 400}@example.com"
    post admin_sign_in_url, params: { email_address: long, password: "x" }
    stored = Audit::Event.where(action: "session.failed").order(:id).last.metadata["email_address"]
    assert_equal 254, stored.length
    assert_equal long.first(254), stored
  end

  test "signing in and out records session.created and session.destroyed as the user" do
    post admin_sign_in_url, params: { email_address: "admin@example.com", password: "password12345" }
    created = Audit::Event.find_by!(action: "session.created")
    assert_equal @user, created.actor
    assert_equal @user, created.subject
    assert_not_includes created.attributes.to_json, "password12345"

    delete admin_sign_out_url
    destroyed = Audit::Event.find_by!(action: "session.destroyed")
    assert_equal @user, destroyed.actor
    assert_equal @user, destroyed.subject
  end

  # A passkey challenge's cookie (`PasskeyChallenges`) is the signed-out
  # person's, so signing out drops every one the browser holds.
  test "signing out deletes every passkey challenge's cookie" do
    post admin_sign_in_url, params: { email_address: "admin@example.com", password: "password12345" }
    names = PasskeyChallenges.cookie_names
    assert_equal %w[cs_passkey_sign_in cs_passkey_second_factor cs_passkey_confirm cs_passkey_register], names
    names.each { |name| cookies[name] = "kept" }

    delete admin_sign_out_url

    written = Array(response.headers["Set-Cookie"]).flat_map { |line| line.split("\n") }
    names.each do |name|
      assert written.any? { |line| line.start_with?("#{name}=;") && line.include?("path=/") }, "#{name} is deleted: #{written.inspect}"
      assert cookies[name].blank?, name
    end
  end

  # A WebSocket is authenticated once, at connect: signing out disconnects
  # the user's cable (`Session#disconnect_cable`), and the cookie's session
  # is no session any more.
  test "signing out disconnects the user's cable and nobody else's" do
    other = User.create!(email_address: "other@example.com", password: "password12345")
    Session.start(user: other, method: "password", user_agent: nil, ip_address: nil)
    post admin_sign_in_url, params: { email_address: "admin@example.com", password: "password12345" }
    session = @user.sessions.sole

    delete admin_sign_out_url

    assert_not Session.exists?(session.id)
    assert_equal [ { "type" => "disconnect", "reconnect" => true } ],
      broadcasts("action_cable/#{@user.to_gid_param}").map { |payload| ActiveSupport::JSON.decode(payload) }
    assert_empty broadcasts("action_cable/#{other.to_gid_param}")
  end

  test "an idle-expired session sends the next request to sign-in" do
    freeze_time
    post admin_sign_in_url, params: { email_address: "admin@example.com", password: "password12345" }
    get "/cs-studio"
    assert_response :success

    travel 12.hours do
      get "/cs-studio"
    end

    assert_redirected_to "/cs-studio/sign-in"
    assert_empty @user.sessions
  end

  ENDED_SENTENCE = "Your session ended. Sign in again.".freeze

  def sign_in_cookie_value
    post admin_sign_in_url, params: { email_address: "admin@example.com", password: "password12345" }
    cookies[:session_id]
  end

  def cookie_cleared?
    Array(response.headers["Set-Cookie"]).join("\n").lines.any? { |line| line.start_with?("session_id=") && line.include?("1970") }
  end

  test "a session ended elsewhere says so once to the browser it ended in, and clears the cookie" do
    sign_in_cookie_value
    @user.sessions.sole.destroy!

    get "/cs-studio"
    assert_redirected_to "/cs-studio/sign-in"
    assert cookie_cleared?
    follow_redirect!
    assert_select "#flash-session-ended[role=note]", text: ENDED_SENTENCE
    assert_select "#alert", count: 0

    get admin_sign_in_url
    assert_no_match ENDED_SENTENCE, response.body
    get "/cs-studio"
    follow_redirect!
    assert_no_match ENDED_SENTENCE, response.body
  end

  # A script's fetch that meets the gone session before any page does (an
  # autosave's PATCH, a stream, JSON, an XHR) follows the redirect inside
  # the fetch, where the sign-in page would spend the flash unseen: it is
  # told nothing and the cookie stays, so the person's next page says it.
  test "a fetch that meets a gone session first spends nothing, and the next page says it" do
    sign_in_cookie_value
    @user.sessions.sole.destroy!

    [
      -> { patch "/cs-studio/account/profile", params: { name: "x" }, headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" } },
      -> { get "/cs-studio", headers: { "Accept" => "application/json" } },
      -> { get "/cs-studio", xhr: true }
    ].each do |fetch|
      fetch.call
      assert_redirected_to "/cs-studio/sign-in"
      assert_not cookie_cleared?, "a fetch leaves the cookie"
      follow_redirect!
      assert_no_match ENDED_SENTENCE, response.body
    end

    get "/cs-studio"
    assert cookie_cleared?
    follow_redirect!
    assert_select "#flash-session-ended[data-turbo-temporary]", text: ENDED_SENTENCE
  end

  # Turbo's own GET (a Drive visit, a frame's load, a prefetch) and a frame's
  # GET are answered with a page Turbo may not draw, so the browser loads the
  # address whole; nothing is spent or cleared until that load, which is told.
  test "Turbo's GET of a gone session asks for a whole load and spends nothing" do
    sign_in_cookie_value
    @user.sessions.sole.destroy!

    [
      { "Turbo-Frame" => "content", "X-Turbo-Request-Id" => SecureRandom.uuid },
      { "X-Turbo-Request-Id" => SecureRandom.uuid },
      { "X-Turbo-Request-Id" => SecureRandom.uuid, "X-Sec-Purpose" => "prefetch" },
      { "Turbo-Frame" => "notes" }
    ].each do |headers|
      get "/cs-studio/posts", headers: headers.merge("Accept" => "text/html, application/xhtml+xml")
      assert_response :success
      assert_select "head meta[name=turbo-visit-control][content=reload]"
      assert_select "turbo-frame", count: 0
      assert_not cookie_cleared?
    end

    get "/cs-studio/posts"
    assert_redirected_to "/cs-studio/sign-in"
    assert cookie_cleared?
    follow_redirect!
    assert_select "#flash-session-ended", text: ENDED_SENTENCE
  end

  test "an idle-expired session says so at sign-in" do
    freeze_time
    sign_in_cookie_value
    travel 12.hours do
      get "/cs-studio"
    end
    follow_redirect!
    assert_select "#flash-session-ended", text: ENDED_SENTENCE
  end

  test "the ended sentence names no email" do
    sign_in_cookie_value
    @user.sessions.sole.destroy!
    get "/cs-studio"
    follow_redirect!
    assert_no_match "admin@example.com", response.body
  end

  test "signing out says nothing at sign-in" do
    sign_in_cookie_value
    delete admin_sign_out_url
    follow_redirect!
    assert_no_match ENDED_SENTENCE, response.body
    get "/cs-studio"
    follow_redirect!
    assert_no_match ENDED_SENTENCE, response.body
  end

  test "a browser with no cookie, or a forged one, is told nothing" do
    get "/cs-studio"
    follow_redirect!
    assert_no_match ENDED_SENTENCE, response.body

    cookies[:session_id] = "forged-unsigned-value"
    get "/cs-studio"
    follow_redirect!
    assert_no_match ENDED_SENTENCE, response.body
  end

  test "the ended sentence does not stand with a refusal alert" do
    sign_in_cookie_value
    @user.sessions.sole.destroy!
    get "/cs-studio"
    post admin_sign_in_url, params: { email_address: "admin@example.com", password: "wrong" }
    follow_redirect!
    assert_select "#alert", text: /Try another/
    assert_no_match ENDED_SENTENCE, response.body
  end

  # The expiry's span (`auth.session`) is drawn only for a session ended at
  # this request, as a child of the request's server span, and says only
  # why: the user's email and the session's id are planted and searched for
  # in everything every exported span writes.
  test "an expired session's request exports one auth.session span with its reason and nothing else" do
    freeze_time
    email = "planted-#{SecureRandom.hex(6)}@planted-#{SecureRandom.hex(6)}.test"
    user = User.create!(email_address: email, password: "password12345")
    planted_id = 10**11 + SecureRandom.random_number(10**11)
    session = Session.start(user: user, method: "password", user_agent: nil, ip_address: nil)
    Session.where(id: session.id).update_all(id: planted_id)
    jar = ActionDispatch::TestRequest.create.cookie_jar
    jar.signed[:session_id] = planted_id
    cookies[:session_id] = jar[:session_id]
    exporter = Rails.application.config.x.otel_test_exporter

    exporter.reset
    get "/cs-studio"
    assert_response :success
    assert_empty exporter.finished_spans.select { |span| span.name == "auth.session" }, "a live request draws no auth.session"

    exporter.reset
    travel 12.hours do
      get "/cs-studio"
    end
    spans = exporter.finished_spans

    assert_redirected_to "/cs-studio/sign-in"
    expiry = spans.select { |span| span.name == "auth.session" }.sole
    root = spans.select { |span| span.parent_span_id == OpenTelemetry::Trace::INVALID_SPAN_ID }.sole
    assert_equal :server, root.kind
    assert_equal root.span_id, expiry.parent_span_id, "auth.session is a child of the request's server span"
    assert_equal({ "auth.session.reason" => "expired_idle" }, expiry.attributes.to_h)

    written = spans.map do |span|
      [ span.name, span.attributes.to_a, span.status&.description, Array(span.links).map { |link| link.attributes.to_a },
        Array(span.events).map { |event| [ event.name, event.attributes.to_a ] } ].flatten.compact.join(" ")
    end.join("\n")
    local, domain = email.split("@")
    [ email, local, domain, CGI.escape(email), planted_id.to_s ].each do |value|
      assert_not_includes written, value, "a span holds #{value}"
    end
  end
end
