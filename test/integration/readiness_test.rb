require "test_helper"

class ReadinessTest < ActionDispatch::IntegrationTest
  teardown { ReadinessController.probes = nil }

  test "GET /ready answers ok, as plain text nothing may keep and with no cookie" do
    get "/ready"

    assert_response :success
    assert_equal "ok", response.body
    assert_equal "text/plain", response.media_type
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_nil response.headers["Set-Cookie"]
  end

  test "the default probes ask the primary database, and the queue's only under Solid Queue" do
    assert_equal 1, ReadinessController.default_probes.size
    original = ActiveJob::Base.queue_adapter
    begin
      ActiveJob::Base.queue_adapter = :solid_queue
      assert_equal 2, ReadinessController.default_probes.size
    ensure
      ActiveJob::Base.queue_adapter = original
    end
  end

  test "an unreachable database is a 503 and never a 500" do
    [ PG::ConnectionBad, ActiveRecord::ConnectionNotEstablished ].each do |error|
      ReadinessController.probes = [ -> { raise error, "password=hunter2" } ]

      get "/ready"

      assert_response :service_unavailable, error.name
      assert_equal "unavailable", response.body
      assert_equal "no-store", response.headers["Cache-Control"]
      assert_nil response.headers["Set-Cookie"]
    end
  end

  test "a failed probe writes one log line with the class and no message" do
    ReadinessController.probes = [ -> { raise PG::ConnectionBad, "password=hunter2" } ]
    io = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    begin
      get "/ready"
    ensure
      Rails.logger = original
    end

    lines = io.string.lines.grep(/Readiness/)
    assert_equal 1, lines.size
    assert_includes lines.first, "PG::ConnectionBad"
    assert_not_includes io.string, "hunter2"
  end

  test "one failing probe among several makes it a 503" do
    ReadinessController.probes = [ -> { true }, -> { raise ActiveRecord::ConnectionNotEstablished } ]

    get "/ready"

    assert_response :service_unavailable
  end

  test "it answers on the public host and on ADMIN_HOST" do
    with_site_address("https://docs.example.org") do
      with_admin_address("https://studio.example.internal") do
        %w[docs.example.org studio.example.internal].each do |host|
          host! host
          get "/ready"
          assert_response :success, host
        end
      end
    end
  end

  test "it answers while setup is pending" do
    start_fresh_install

    get "/ready", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_equal "ok", response.body
  end
end
