require "test_helper"

# The Sessions card's two endings: a row's End, answered as a stream that
# takes the row away whether or not anything ended, and "Sign out everywhere
# else", which keeps the session it is asked from.
class Admin::AccountSessionsControllerTest < ActionDispatch::IntegrationTest
  STREAM = "text/vnd.turbo-stream.html".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @user = users(:reader)
    sign_in_as @user
    @current = Current.session
  end

  def start(user = @user) = Session.start(user: user, method: "password", user_agent: nil, ip_address: nil)

  def end_session(id)
    delete admin_account_session_path(id), headers: { "Accept" => STREAM }
  end

  # The answer every End gets: the row removed, the foot drawn again, one toast.
  def assert_end_answer(id, toast:, others:)
    assert_response :ok
    assert_equal STREAM, response.media_type
    assert_select "turbo-stream[action=remove][target=session-#{id}]"
    assert_select "turbo-stream[action=replace][target=account-sessions-foot] template", text: /#{Regexp.escape(others)}/
    assert_select "turbo-stream[action=append][target=toasts] template", text: /#{Regexp.escape(toast)}/
  end

  def still_signed_in
    get admin_account_path
    assert_response :ok
  end

  test "End of one of my other sessions ends it and says so" do
    other = start
    start

    end_session(other.id)

    assert_end_answer(other.id, toast: "Session ended.", others: "1 other session")
    assert_not Session.exists?(other.id)
    event = Audit::Event.where(action: "session.ended").sole
    assert_equal({ "reason" => "ended_by_self", "count" => 1 }, event.metadata)
    assert_equal @user, event.actor
  end

  test "End of another user's session id ends nothing, records nothing, and answers as for one of mine already gone" do
    theirs = start(users(:author))
    mine = start
    mine.destroy!

    end_session(theirs.id)
    assert_end_answer(theirs.id, toast: "That session had already ended.", others: "You're not signed in anywhere else.")
    stranger = response.body.gsub(theirs.id.to_s, "ID")

    end_session(mine.id)
    assert_end_answer(mine.id, toast: "That session had already ended.", others: "You're not signed in anywhere else.")
    assert_equal response.body.gsub(mine.id.to_s, "ID"), stranger, "an id tells nothing about whose it is"

    assert Session.exists?(theirs.id)
    assert_empty Audit::Event.where(action: "session.ended")
  end

  test "End of my own current session ends nothing and I stay signed in" do
    end_session(@current.id)

    assert_end_answer(@current.id, toast: "That session had already ended.", others: "You're not signed in anywhere else.")
    assert Session.exists?(@current.id)
    assert_empty Audit::Event.where(action: "session.ended")
    still_signed_in
  end

  test "End without Turbo goes back to the card with the toast" do
    other = start

    delete admin_account_session_path(other.id)

    assert_redirected_to admin_account_path(anchor: "sessions")
    assert_equal "Session ended.", flash[:notice]
    assert_not Session.exists?(other.id)
  end

  test "Sign out everywhere else ends every other session, keeps this one, and I stay signed in" do
    others = 2.times.map { start }
    bystander = start(users(:author))

    delete admin_account_sessions_path

    assert_redirected_to admin_account_path(anchor: "sessions")
    assert_equal "Signed out of 2 other sessions.", flash[:notice]
    others.each { |session| assert_not Session.exists?(session.id) }
    assert Session.exists?(@current.id), "the session the person acts in survives"
    assert Session.exists?(bystander.id)
    assert_equal({ "reason" => "ended_by_self", "count" => 2 }, Audit::Event.where(action: "session.ended").sole.metadata)
    still_signed_in
  end

  test "Sign out everywhere else with one other says one" do
    start

    delete admin_account_sessions_path

    assert_equal "Signed out of 1 other session.", flash[:notice]
  end

  test "signed out, both go to the sign-in and end nothing" do
    other = start
    sign_out

    end_session(other.id)
    assert_redirected_to admin_sign_in_path
    delete admin_account_sessions_path
    assert_redirected_to admin_sign_in_path
    assert Session.exists?(other.id)
  end
end
