require "test_helper"

class SignIn::Sessions::EndAllTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    @user = users(:reader)
    @owner = users(:one)
  end

  test "an owner ends every session of the user and records one event with the count" do
    sessions = 3.times.map { start(@user) }
    mine = start(@owner)

    result = Current.set(session: mine) { as(@owner) { SignIn::Sessions::EndAll.call(@user) } }

    assert result.ok?, result.errors.inspect
    assert_equal 3, result.record
    sessions.each { |session| assert_not Session.exists?(session.id) }
    assert Session.exists?(mine.id)
    event = Audit::Event.where(action: "session.ended").sole
    assert_equal({ "reason" => "ended_by_owner", "count" => 3 }, event.metadata)
    assert_equal @owner, event.actor
    assert_equal @user, event.subject
    assert_equal 3, broadcasts("action_cable/#{@user.to_gid_param}").size, "each ended row went through destroy, so the cable was told"
  end

  test "with no session open nothing is recorded" do
    result = as(@owner) { SignIn::Sessions::EndAll.call(@user) }

    assert result.ok?
    assert_equal 0, result.record
    assert_not Audit::Event.exists?(action: "session.ended")
  end

  test "an admin who is not an owner is denied and nothing is ended" do
    session = start(@user)

    result = as(users(:two)) { SignIn::Sessions::EndAll.call(@user) }

    assert result.denied?
    assert Session.exists?(session.id)
    assert_not Audit::Event.exists?(action: "session.ended")
    assert_equal "users.manage", Audit::Event.where(action: "access.denied").sole.metadata["permission"]
  end

  test "an owner's own account is refused: that is Sign out everywhere else" do
    session = start(@owner)

    result = as(@owner) { SignIn::Sessions::EndAll.call(@owner) }

    assert_not result.ok?
    assert_not result.denied?
    assert_equal [ "End your own sessions from Your account." ], result.errors
    assert Session.exists?(session.id)
    assert_not Audit::Event.exists?(action: "session.ended")
  end

  private

  def start(user) = Session.start(user: user, method: "password", user_agent: nil, ip_address: nil)
end
