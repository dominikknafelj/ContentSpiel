module SetupTestHelper
  # A brand-new install: no users, setup not completed. `delete_all`, not
  # `destroy_all` -- since Task 8's `User#ensure_not_last_owner` (a
  # `before_destroy`), destroying the fixture users one at a time would
  # refuse to remove the second one (by then, the only one left), leaving
  # this "fresh" install with a leftover user and `User.none?`-gated setup
  # steps (e.g. `create_setup_admin` below) redirected away as already
  # provisioned. Skipping callbacks is fine here: this is test cleanup of
  # fixture rows with no sessions/tokens attached yet, not a real delete a
  # real invariant needs to run against.
  def start_fresh_install
    User.delete_all
    site_settings(:default).update!(setup_completed_at: nil)
    SetupController::RATE_LIMIT_STORE.clear if defined?(SetupController::RATE_LIMIT_STORE)
  end

  def verify_setup_token
    patch setup_step_path("token"), params: { token: Setup::Token.value }
  end

  def create_setup_admin(email: "owner@example.com")
    patch setup_step_path("admin"), params: { user: {
      email_address: email, password: "password12345", password_confirmation: "password12345"
    } }
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include SetupTestHelper
end
