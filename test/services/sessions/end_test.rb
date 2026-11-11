require "test_helper"

class Sessions::EndTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    @user = users(:reader)
    @session = Session.start(user: @user, method: "password", user_agent: nil, ip_address: nil)
  end

  test "destroys the row and records session.ended with its reason, as the actor" do
    result = Sessions::End.call(@session, reason: "ended_by_owner", actor: users(:one))

    assert result.ok?, result.errors.inspect
    assert_not Session.exists?(@session.id)
    event = Audit::Event.where(action: "session.ended").sole
    assert_equal({ "reason" => "ended_by_owner", "count" => 1 }, event.metadata)
    assert_equal users(:one), event.actor
    assert_equal @user, event.subject
    assert_equal 1, broadcasts("action_cable/#{@user.to_gid_param}").size, "the row went through destroy, so the cable was told"
  end

  test "an ending with no actor is recorded with none" do
    as(users(:one)) { Sessions::End.call(@session, reason: "expired_idle", actor: nil) }

    event = Audit::Event.where(action: "session.ended").sole
    assert_nil event.actor_id
    assert_nil event.user_id
  end

  test "a reason outside END_REASONS is refused before anything is written" do
    assert_raises(ArgumentError) { Sessions::End.call(@session, reason: "signed_out", actor: nil) }

    assert Session.exists?(@session.id)
    assert_not Audit::Event.exists?(action: "session.ended")
  end

  test "the ending and its event are one transaction: an event that fails keeps the session" do
    with_singleton_override(Audit, :record, ->(*, **) { raise ActiveRecord::StatementInvalid, "the log is down" }) do
      assert_raises(ActiveRecord::StatementInvalid) { Sessions::End.call(@session, reason: "expired_idle", actor: nil) }
    end

    assert Session.exists?(@session.id)
    assert_empty broadcasts("action_cable/#{@user.to_gid_param}")
  end

  test "a session already gone is ended once: the second call records nothing" do
    stale = Session.find(@session.id)
    Sessions::End.call(@session, reason: "expired_idle", actor: nil)

    result = Sessions::End.call(stale, reason: "expired_idle", actor: nil)

    assert result.ok?
    assert_equal 1, Audit::Event.where(action: "session.ended").count
  end
end
