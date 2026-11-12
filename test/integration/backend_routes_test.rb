require "test_helper"

class BackendRoutesTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
  end

  test "Action Mailbox draws no route" do
    specs = Rails.application.routes.routes.map { |route| route.path.spec.to_s }
    assert_empty specs.grep(%r{\A/rails/(action_mailbox|conductor)})
    assert_not defined?(ActionMailbox::Engine)
  end

  test "Turbo's historical-location routes are not drawn" do
    assert_empty Rails.application.routes.routes.map { |route| route.path.spec.to_s }.grep(/historical_location/)
  end
end
