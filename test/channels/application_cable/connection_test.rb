require "test_helper"

# Who may open the cable (notes spec §6.2): a CS Studio session, read from
# the same signed cookie the controllers read (`Authentication`), and nobody
# else. `/cable` is one address for the whole app, so this is what keeps it
# CS Studio's.
class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  test "a CS Studio session connects as its user" do
    session = Session.start(user: users(:reader), method: "password", user_agent: nil, ip_address: nil)
    cookies.signed[:session_id] = session.id

    connect

    assert_equal users(:reader), connection.current_user
  end

  test "no session, no connection" do
    assert_reject_connection { connect }

    cookies.signed[:session_id] = 0
    assert_reject_connection { connect }
  end

  test "a session that was ended, and an id that is not signed, are no session" do
    session = Session.start(user: users(:reader), method: "password", user_agent: nil, ip_address: nil)
    cookies[:session_id] = session.id.to_s
    assert_reject_connection { connect }

    cookies.signed[:session_id] = session.id
    session.destroy!
    assert_reject_connection { connect }
  end

  # The cable resumes a session through the same lookup as a request, so a
  # cookie past its session's end is refused here too, and the row ended.
  test "an expired cookie is refused at connect" do
    session = Session.start(user: users(:reader), method: "password", user_agent: nil, ip_address: nil, at: 15.days.ago)
    cookies.signed[:session_id] = session.id

    assert_reject_connection { connect }

    assert_not Session.exists?(session.id)
    assert_equal "expired_absolute", Audit::Event.where(action: "session.ended").sole.metadata["reason"]
  end

  # The connect runs outside any request's span: an `auth.session` there would
  # be a root the sampler drops, so the cable's expiry is audited, not traced.
  test "an expiry met at connect is audited and draws no span" do
    session = Session.start(user: users(:reader), method: "password", user_agent: nil, ip_address: nil, at: 13.hours.ago)
    cookies.signed[:session_id] = session.id
    exporter = Rails.application.config.x.otel_test_exporter
    exporter.reset

    assert_reject_connection { connect }

    assert_empty exporter.finished_spans.select { |span| span.name == "auth.session" }
    assert_equal "expired_idle", Audit::Event.where(action: "session.ended").sole.metadata["reason"]
  end
end
