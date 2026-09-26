module SetupTestHelper
  # A brand-new install: no users, setup not completed.
  def start_fresh_install
    User.destroy_all
    site_settings(:default).update!(setup_completed_at: nil)
    SetupController::RATE_LIMIT_STORE.clear if defined?(SetupController::RATE_LIMIT_STORE)
  end

  def verify_setup_token
    patch setup_step_path("token"), params: { token: Setup::Token.value }
  end

  def create_setup_admin(email: "owner@example.com")
    patch setup_step_path("admin"), params: { user: {
      email_address: email, password: "password123", password_confirmation: "password123"
    } }
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include SetupTestHelper
end
