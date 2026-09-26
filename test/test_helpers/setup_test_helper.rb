module SetupTestHelper
  # A brand-new install: no users, setup not completed.
  def start_fresh_install
    User.destroy_all
    site_settings(:default).update!(setup_completed_at: nil)
    SetupController::RATE_LIMIT_STORE.clear if defined?(SetupController::RATE_LIMIT_STORE)
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include SetupTestHelper
end
