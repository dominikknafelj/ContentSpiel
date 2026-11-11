require "test_helper"

class Sessions::EndOthersTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    @user = users(:reader)
    @current = start(@user)
  end

  test "ends every session of the user but the one kept, and records one event with the count" do
    others = 2.times.map { start(@user) }
    bystander = start(users(:author))

    result = as(@user) { Sessions::EndOthers.call(user: @user, keep: @current) }

    assert result.ok?, result.errors.inspect
    assert_equal 2, result.record
    assert Session.exists?(@current.id), "the session the person acts in survives"
    others.each { |session| assert_not Session.exists?(session.id) }
    assert Session.exists?(bystander.id)
    event = Audit::Event.where(action: "session.ended").sole
    assert_equal({ "reason" => "ended_by_self", "count" => 2 }, event.metadata)
    assert_equal @user, event.actor
    assert_equal @user, event.subject
    assert_equal 2, broadcasts("action_cable/#{@user.to_gid_param}").size, "each ended row went through destroy, so the cable was told"
  end

  test "the defaults are the signed-in user and the session they act in" do
    other = start(@user)

    result = Current.set(session: @current) { as(@user) { Sessions::EndOthers.call } }

    assert result.ok?, result.errors.inspect
    assert_equal 1, result.record
    assert Session.exists?(@current.id)
    assert_not Session.exists?(other.id)
  end

  test "with no other session open nothing is ended and nothing recorded" do
    result = as(@user) { Sessions::EndOthers.call(user: @user, keep: @current) }

    assert result.ok?
    assert_equal 0, result.record
    assert Session.exists?(@current.id)
    assert_not Audit::Event.exists?(action: "session.ended")
  end

  test "only: ends that one session of the user, and records it with a count of one" do
    target = start(@user)
    untouched = start(@user)

    result = as(@user) { Sessions::EndOthers.call(user: @user, keep: @current, only: target.id) }

    assert result.ok?
    assert_equal 1, result.record
    assert_not Session.exists?(target.id)
    assert Session.exists?(untouched.id)
    assert Session.exists?(@current.id)
    assert_equal({ "reason" => "ended_by_self", "count" => 1 }, Audit::Event.where(action: "session.ended").sole.metadata)
  end

  # An id that is not one of yours answers exactly as one of
  # yours that had already ended, so the id tells nothing.
  test "only: another user's session, an unknown id or the kept one ends nothing and records nothing" do
    theirs = start(users(:author))
    gone = start(@user).tap(&:destroy!)

    [ theirs.id, gone.id, "not-an-id", @current.id ].each do |id|
      result = as(@user) { Sessions::EndOthers.call(user: @user, keep: @current, only: id) }

      assert result.ok?, "#{id.inspect}: #{result.errors.inspect}"
      assert_equal 0, result.record, id.inspect
    end
    assert Session.exists?(theirs.id)
    assert Session.exists?(@current.id)
    assert_not Audit::Event.exists?(action: "session.ended")
  end

  test "someone else's sessions are refused, even for a holder of users.manage" do
    other = start(@user)

    result = as(users(:two)) { Sessions::EndOthers.call(user: @user, keep: nil) }

    assert result.denied?
    assert Session.exists?(other.id)
    assert_not Audit::Event.exists?(action: "session.ended")
    assert Audit::Event.exists?(action: "access.denied")
  end

  test "the ending and its event are one transaction: an event that fails keeps every session" do
    other = start(@user)

    with_singleton_override(Audit, :record, ->(*, **) { raise ActiveRecord::StatementInvalid, "the log is down" }) do
      assert_raises(ActiveRecord::StatementInvalid) { as(@user) { Sessions::EndOthers.call(user: @user, keep: @current) } }
    end

    assert Session.exists?(other.id)
  end

  private

  def start(user) = Session.start(user: user, method: "password", user_agent: nil, ip_address: nil)
end
