require "test_helper"

# A throttle trip on a CS Studio door is one `request.limited` event, the
# first refusal of a window; a public door and a failure record nothing.
class Audit::RequestLimitsTest < ActiveSupport::TestCase
  Request = Struct.new(:controller_instance)

  def payload(controller, count: 11, to: 10, name: nil)
    { request: Request.new(controller), count:, to:, within: 3.minutes, by: "digest-of-an-address", name:, scope: nil, cache_key: "rate-limit:secret-key" }
  end

  def door(klass, action)
    klass.new.tap { |controller| controller.action_name = action }
  end

  def limited = Audit::Event.where(action: "request.limited")

  test "the first refusal records one event naming the door and the default limit, and holds no key" do
    assert_difference -> { limited.count }, 1 do
      Audit::RequestLimits.heard(payload(door(Admin::PasswordsController, "create")))
    end
    metadata = limited.sole.metadata
    assert_equal({ "limit" => "default", "door" => "admin/passwords#create" }, metadata)
    assert_no_match(/digest|secret/, limited.sole.to_json)
  end

  test "a named limit is the limit" do
    Audit::RequestLimits.heard(payload(door(Admin::PasswordsController, "check"), name: "check"))
    assert_equal "check", limited.sole.metadata["limit"]
  end

  test "a later refusal of the same window records nothing" do
    assert_no_difference -> { limited.count } do
      Audit::RequestLimits.heard(payload(door(Admin::PasswordsController, "create"), count: 12))
    end
  end

  test "a public door records nothing" do
    [ PublicController, FormSendsController ].each do |klass|
      assert_no_difference -> { limited.count } do
        Audit::RequestLimits.heard(payload(door(klass, "show")))
      end
    end
  end

  test "a failure logs one line of its class and does not raise" do
    lines = []
    logger = Object.new
    logger.define_singleton_method(:error) { |line| lines << line }
    with_singleton_override(Rails, :logger, -> { logger }) do
      with_singleton_override(Audit, :record, ->(*, **) { raise "password=hunter2" }) do
        Audit::RequestLimits.heard(payload(door(Admin::PasswordsController, "create")))
      end
    end
    assert_equal 1, lines.size
    assert_no_match(/hunter2/, lines.first)
  end

  test "a payload with no controller records nothing and does not raise" do
    assert_no_difference -> { limited.count } do
      Audit::RequestLimits.heard(payload(nil))
    end
  end
end
