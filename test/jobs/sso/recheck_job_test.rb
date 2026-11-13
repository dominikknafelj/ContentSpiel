require "test_helper"

# The daily re-check of the sessions an outside provider made: SSO's through
# its refresh token, a gem's through its entry's `recheck`.
class Sso::RecheckJobTest < ActiveJob::TestCase
  include LogCapture

  setup do
    @user = link_to_sso(users(:one), subject: "sub-1")
    @t = Time.zone.local(2026, 11, 11, 9, 0, 0)
    @exporter = Rails.application.config.x.otel_test_exporter
  end

  teardown { Rails.application.reloader.prepare! }

  def start(token:, at:, method: "sso")
    Session.start(user: @user, method: method, user_agent: nil, ip_address: nil, provider_token: token, at: at)
  end

  def token_posts(idp) = idp.requests.count { |request| request.path == "/idp/token" }

  def ended_events = Audit::Event.where(action: "session.ended").order(:id)

  # The job under a CONSUMER span, as Solid Queue runs it, so its own span is
  # recorded; answers the finished spans. Every session is seen just before,
  # as one in use is: an idle session is over and is not asked.
  def run_at(at)
    Session.update_all(last_seen_at: at) # version: none (a test's own rows)
    @exporter.reset
    Telemetry.tracer.in_span("job", kind: :consumer) { Sso::RecheckJob.perform_now(at: at) }
    @exporter.finished_spans
  end

  def run_span(spans) = spans.find { |span| span.name == "auth.sso.recheck_run" }

  def counts(spans)
    run_span(spans).attributes.slice("auth.sso.recheck.checked", "auth.sso.recheck.ok", "auth.sso.recheck.revoked",
      "auth.sso.recheck.unavailable", "auth.session.count")
  end

  def counted(checked: 0, ok: 0, revoked: 0, unavailable: 0, ended: 0)
    { "auth.sso.recheck.checked" => checked, "auth.sso.recheck.ok" => ok, "auth.sso.recheck.revoked" => revoked,
      "auth.sso.recheck.unavailable" => unavailable, "auth.session.count" => ended }
  end

  test "revoked ends the session, unavailable keeps it until the grace is spent, a rotated token is stored, and no token ends at 24 hours" do
    with_fake_idp(refresh_token: "rt-1") do |idp|
      held = start(token: "rt-1", at: @t)
      bare = start(token: nil, at: @t)

      # A rotated token is stored and the check date moves to the run's.
      idp.rotate_refresh_token("rt-2")
      spans = run_at(@t + 24.hours)
      assert_equal counted(checked: 1, ok: 1), counts(spans)
      assert_equal [ @t + 24.hours, "rt-2" ], held.reload.then { |row| [ row.provider_checked_at, row.provider_token ] }
      raw = Session.connection.select_value("SELECT provider_token FROM sessions WHERE id = #{held.id.to_i}") # sql: a test reads the raw column
      assert_not_includes raw, "rt-2", "the rotated token is stored encrypted"
      assert_equal 1, token_posts(idp), "the session with no token is never sent"
      assert_equal 1, spans.count { |span| span.name == "auth.sso.recheck" }, "Refresh's own span, one per session, and no second"
      assert_equal @t, bare.reload.provider_checked_at

      # No token: the sweep ends it at 24 hours.
      Sessions::SweepJob.perform_now(at: @t + 24.hours)
      assert_nil Session.find_by(id: bare.id)
      assert_equal({ "reason" => "expired_sso", "count" => 1, "after_hours" => 24 }, ended_events.last.metadata)
      assert Session.exists?(held.id)

      # invalid_grant: ended at once, as sso_revoked.
      idp.revoke!
      assert_difference -> { ended_events.count }, 1 do
        assert_equal counted(checked: 1, revoked: 1, ended: 1), counts(run_at(@t + 48.hours))
      end
      assert_nil Session.find_by(id: held.id)
      event = ended_events.last
      assert_equal [ "sso_revoked", 1 ], [ event.metadata["reason"], event.metadata["count"] ]
      assert_equal @user, event.subject
      assert_nil event.actor

      # Unreachable: three hourly runs leave the check date where the last
      # good check put it, the one past the grace asks nothing, and the sweep
      # ends the session at the 26-hour mark.
      down = start(token: "rt-2", at: @t + 48.hours)
      idp.down!
      [ 72, 73 ].each do |hours|
        assert_equal counted(checked: 1, unavailable: 1), counts(run_at(@t + hours.hours)), "at #{hours}h"
        assert_equal @t + 48.hours, down.reload.provider_checked_at
      end
      assert_equal counted, counts(run_at(@t + 74.hours)), "a session past its grace is not asked again, so an answer cannot keep it"
      assert_equal @t + 48.hours, down.reload.provider_checked_at

      Sessions::SweepJob.perform_now(at: @t + 74.hours - 1.second)
      assert Session.exists?(down.id)
      Sessions::SweepJob.perform_now(at: @t + 74.hours)
      assert_nil Session.find_by(id: down.id)
      assert_equal({ "reason" => "expired_sso", "count" => 1, "after_hours" => 26 }, ended_events.last.metadata)
    end
  end

  test "a session checked less than 24 hours ago is not sent to the provider" do
    with_fake_idp(refresh_token: "rt-1") do |idp|
      session = start(token: "rt-1", at: @t)

      assert_equal counted, counts(run_at(@t + 24.hours - 1.second))
      assert_equal 0, token_posts(idp)
      assert_equal @t, session.reload.provider_checked_at
    end
  end

  test "an SSO session is left alone while single sign-on is not configured, and ends by the sweep" do
    session = start(token: "rt-1", at: @t)

    assert_equal counted, counts(run_at(@t + 24.hours))
    assert_equal @t, session.reload.provider_checked_at

    Sessions::SweepJob.perform_now(at: @t + 26.hours - 1.second)
    assert Session.exists?(session.id)
    Sessions::SweepJob.perform_now(at: @t + 26.hours)
    assert_nil Session.find_by(id: session.id)
    assert_equal({ "reason" => "expired_sso", "count" => 1, "after_hours" => 26 }, ended_events.last.metadata)
  end

  # The token cannot be decrypted without the keys, so its session cannot be
  # asked: that session is unavailable, the gems are still asked, and the
  # session ends by expiry at 26 hours, which reads no token.
  test "without encryption keys an SSO session is unavailable, the run goes on, and the sweep ends it at 26 hours" do
    with_fake_idp(refresh_token: "rt-1") do |idp|
      session = start(token: "rt-1", at: @t)
      asked = []
      SignInMethods.register("acme/saml", label: "acme.sign_in.saml", path: :admin_root_path, recheck: ->(row) { asked << row.id; :ok })
      gem_session = start(token: nil, at: @t, method: "acme/saml")

      without_encryption_keys do
        report = assert_error_reported(Sso::RecheckJob::RecheckFailed) do
          assert_equal counted(checked: 2, ok: 1, unavailable: 1), counts(run_at(@t + 24.hours))
        end
        assert_equal "ActiveRecord::Encryption::Errors::Configuration", report.error.message
        assert_equal 0, token_posts(idp)
        assert_equal [ gem_session.id ], asked
        assert_equal @t, session.reload.provider_checked_at

        Session.update_all(last_seen_at: @t + 26.hours) # version: none (a test's own rows)
        assert_nil session.reload.expiry(@t + 26.hours - 1.second)
        Sessions::SweepJob.perform_now(at: @t + 26.hours)
      end
      assert_nil Session.find_by(id: session.id)
      assert_equal({ "reason" => "expired_sso", "count" => 1, "after_hours" => 26 }, ended_events.last.metadata)
    end
  end

  test "a session whose account was unlinked is ended as revoked without asking" do
    with_fake_idp(refresh_token: "rt-1") do |idp|
      session = start(token: "rt-1", at: @t)
      @user.update_columns(sso_issuer: nil, sso_subject: nil, sso_linked_at: nil) # version: none (a test's setup)

      assert_equal counted(checked: 1, revoked: 1, ended: 1), counts(run_at(@t + 24.hours))
      assert_nil Session.find_by(id: session.id)
      assert_equal 0, token_posts(idp)
    end
  end

  test "a gem's recheck is called for its own sessions, and one that raises ends nothing and stops nothing" do
    asked = []
    SignInMethods.register("acme/saml", label: "acme.sign_in.saml", path: :admin_root_path,
      recheck: ->(session) { asked << session.id; session.ip_address == "192.0.2.9" ? :revoked : :ok })
    SignInMethods.register("acme/broken", label: "acme.sign_in.broken", path: :admin_root_path,
      recheck: ->(_session) { raise IOError, "planted-gem-message" })
    SignInMethods.register("acme/odd", label: "acme.sign_in.odd", path: :admin_root_path,
      recheck: ->(_session) { "planted-odd-answer" })
    SignInMethods.register("acme/never", label: "acme.sign_in.never", path: :admin_root_path)

    broken = start(token: nil, at: @t, method: "acme/broken")
    kept = start(token: nil, at: @t, method: "acme/saml")
    gone = start(token: nil, at: @t, method: "acme/saml").tap { |row| row.update_columns(ip_address: "192.0.2.9") } # version: none (a test's own row)
    fresh = start(token: nil, at: @t + 1.hour, method: "acme/saml")
    sso = start(token: "rt-1", at: @t)
    never = start(token: nil, at: @t, method: "acme/never")
    odd = start(token: nil, at: @t, method: "acme/odd")

    spans = nil
    log = capture_log do
      report = assert_error_reported(Sso::RecheckJob::RecheckFailed) { spans = run_at(@t + 24.hours) }
      assert_equal "IOError", report.error.message, "the class alone, never the gem's message"
    end

    assert_equal [ kept.id, gone.id ].sort, asked.sort, "its own due sessions alone"
    assert_equal counted(checked: 4, ok: 1, revoked: 1, unavailable: 2, ended: 1), counts(spans)
    assert_equal @t + 24.hours, kept.reload.provider_checked_at
    assert_nil Session.find_by(id: gone.id)
    assert_equal "sso_revoked", ended_events.last.metadata["reason"]
    assert_equal @t, broken.reload.provider_checked_at, "a recheck that raised is unavailable"
    assert_equal @t, odd.reload.provider_checked_at, "an answer outside the three is unavailable"
    assert_equal @t + 1.hour, fresh.reload.provider_checked_at
    assert_equal @t, sso.reload.provider_checked_at
    assert Session.exists?(never.id)
    assert_includes log, "acme/odd"
    assert_includes log, "String"
    assert_not_includes log, "planted-odd-answer"
    assert_not_includes log, "planted-gem-message"
  end

  test "a gem's recheck past its limit is unavailable" do
    SignInMethods.register("acme/slow", label: "acme.sign_in.slow", path: :admin_root_path, recheck: ->(_session) { sleep 2; :revoked })
    session = start(token: nil, at: @t, method: "acme/slow")
    stub = Sso::RecheckJob.const_get(:GEM_RECHECK_LIMIT)
    Sso::RecheckJob.send(:remove_const, :GEM_RECHECK_LIMIT)
    Sso::RecheckJob.const_set(:GEM_RECHECK_LIMIT, 0.05)

    report = assert_error_reported(Sso::RecheckJob::RecheckFailed) do
      assert_equal counted(checked: 1, unavailable: 1), counts(run_at(@t + 24.hours))
    end
    assert_equal "Timeout::Error", report.error.message
    assert Session.exists?(session.id)
  ensure
    Sso::RecheckJob.send(:remove_const, :GEM_RECHECK_LIMIT)
    Sso::RecheckJob.const_set(:GEM_RECHECK_LIMIT, stub)
  end

  # The tests below run on the test's one connection (the fixtures pin it),
  # so they show the re-reads, not two runs racing on two connections; the
  # advisory lock's skip is shown with a second connection of libpq's own.
  test "a session signed out after its batch was read is skipped, and a second run asks nothing again" do
    asked = []
    first = nil
    second = nil
    SignInMethods.register("acme/saml", label: "acme.sign_in.saml", path: :admin_root_path,
      recheck: ->(session) { asked << session.id; second.destroy! if session.id == first.id; :ok })
    first = start(token: nil, at: @t, method: "acme/saml")
    second = start(token: nil, at: @t, method: "acme/saml")

    assert_equal counted(checked: 1, ok: 1), counts(run_at(@t + 24.hours))
    assert_equal [ first.id ], asked
    assert_nil Session.find_by(id: second.id), "not resurrected"

    assert_equal counted, counts(run_at(@t + 24.hours))
    assert_equal [ first.id ], asked
  end

  test "an answer for a session signed out or checked again during its ask writes nothing" do
    SignInMethods.register("acme/gone", label: "acme.sign_in.gone", path: :admin_root_path, recheck: ->(row) { row.destroy!; :ok })
    SignInMethods.register("acme/moved", label: "acme.sign_in.moved", path: :admin_root_path,
      recheck: ->(row) { row.update_columns(provider_checked_at: @t + 24.hours); :revoked }) # version: none (a test's stand-in for another run)
    gone = start(token: nil, at: @t, method: "acme/gone")
    moved = start(token: nil, at: @t, method: "acme/moved")

    assert_no_difference -> { ended_events.count } do
      assert_equal counted(checked: 2, ok: 1, revoked: 1), counts(run_at(@t + 24.hours))
    end
    assert_nil Session.find_by(id: gone.id), "not written back"
    assert_equal @t + 24.hours, moved.reload.provider_checked_at, "the other run's check stands"
  end

  test "a session whose lock another run holds is skipped" do
    asked = []
    SignInMethods.register("acme/saml", label: "acme.sign_in.saml", path: :admin_root_path, recheck: ->(row) { asked << row.id; :ok })
    held = start(token: nil, at: @t, method: "acme/saml")
    free = start(token: nil, at: @t, method: "acme/saml")
    config = Session.connection_db_config.configuration_hash
    other = PG.connect(host: config[:host], port: config[:port], dbname: config[:database], user: config[:username],
      password: config[:password], gssencmode: "disable")
    other.exec_params("SELECT pg_advisory_lock($1, $2)", [ Sso::RecheckJob::ADVISORY_NAMESPACE, held.id % Sso::RecheckJob::INT4 ])

    assert_equal counted(checked: 1, ok: 1), counts(run_at(@t + 24.hours))
    assert_equal [ free.id ], asked
    assert_equal @t, held.reload.provider_checked_at
  ensure
    other&.close
  end

  test "more than a batch is checked, each session once" do
    asked = []
    SignInMethods.register("acme/saml", label: "acme.sign_in.saml", path: :admin_root_path,
      recheck: ->(session) { asked << session.id; :unavailable })
    rows = Array.new(3) { start(token: nil, at: @t, method: "acme/saml") }
    stub = Sso::RecheckJob.const_get(:BATCH)
    Sso::RecheckJob.send(:remove_const, :BATCH)
    Sso::RecheckJob.const_set(:BATCH, 2)

    assert_equal counted(checked: 3, unavailable: 3), counts(run_at(@t + 24.hours))
    assert_equal rows.map(&:id).sort, asked.sort
  ensure
    Sso::RecheckJob.send(:remove_const, :BATCH)
    Sso::RecheckJob.const_set(:BATCH, stub)
  end

  test "no token reaches a log line, a span or an audit event" do
    with_fake_idp(refresh_token: "rt-planted-0d9f2a") do |idp|
      start(token: "rt-planted-0d9f2a", at: @t)
      revoked = start(token: "rt-planted-0d9f2a", at: @t + 1.hour)
      idp.rotate_refresh_token("rt-planted-rotated-7c41e8")

      spans = []
      log = capture_log(LogCapture::REQUEST_LOGGERS) do
        spans += run_at(@t + 24.hours)
        idp.revoke!
        spans += run_at(@t + 25.hours)
      end

      assert_nil Session.find_by(id: revoked.id)
      exported = spans.flat_map { |span| [ span.name, *span.attributes.to_a.flatten, *Array(span.events).map(&:attributes) ] }.to_s
      audited = Audit::Event.all.map { |event| [ event.metadata, event.snapshot ] }.to_s
      %w[rt-planted-0d9f2a rt-planted-rotated-7c41e8].each do |token|
        assert_not_includes log, token
        assert_not_includes exported, token
        assert_not_includes audited, token
      end
    end
  end

  test "its span is not a root when run under a parent span" do
    span = run_span(run_at(@t))
    assert_not_equal OpenTelemetry::Trace::INVALID_SPAN_ID, span.parent_span_id
  end

  test "it is scheduled in every environment, hourly on default" do
    %w[production development test].each do |environment|
      schedule = YAML.load_file(Rails.root.join("config/recurring.yml")).dig(environment, "sso_recheck")
      assert_equal({ "class" => "Sso::RecheckJob", "queue" => "default", "schedule" => "every hour at minute 25" }, schedule, environment)
    end
  end
end
