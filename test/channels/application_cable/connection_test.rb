require "test_helper"

# Who may open the cable (notes spec §6.2): a CS Studio session, read from
# the same signed cookie the controllers read (`Authentication`), and nobody
# else. `/cable` is one address for the whole app, so this is what keeps it
# CS Studio's.
class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  test "a CS Studio session connects as its user" do
    session = users(:reader).sessions.create!
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
    session = users(:reader).sessions.create!
    cookies[:session_id] = session.id.to_s
    assert_reject_connection { connect }

    cookies.signed[:session_id] = session.id
    session.destroy!
    assert_reject_connection { connect }
  end
end
