require "test_helper"

# The wizard's passkey step, after the admin account: the founding owner adds
# a passkey there through the step's own endpoints under /cs-studio/setup (the redirect
# constraint keeps CS Studio's closed until setup ends), and is shown the
# recovery codes, whose Done goes on to the site's identity. The policy
# decides whether the step may be skipped; a request with no relying party
# (an IP address) can make no passkey, so the step says so and goes on.
class SetupPasskeyStepTest < ActionDispatch::IntegrationTest
  STREAM = "text/vnd.turbo-stream.html".freeze
  LATER_STEPS = SetupController::STEPS.drop(SetupController::STEPS.index("passkey") + 1).freeze
  REGISTER = "[data-controller~='admin--passkeys--register']".freeze

  def walk_to_passkey_step(policy: "nobody")
    start_fresh_install
    site_settings(:default).update!(passkey_policy: policy)
    verify_setup_token
    create_setup_admin
  end

  def owner = User.find_by!(email_address: "owner@example.com")

  def add_passkey_in_wizard(client: fake_authenticator, name: "MacBook")
    post setup_passkey_options_path, as: :json
    assert_response :success
    options = response.parsed_body
    credential = client.create(challenge: options.fetch("challenge"), rp_id: options.dig("rp", "id"), user_verified: true).to_json
    patch setup_step_path("passkey"), params: { credential: credential, name: name }.to_json,
      headers: { "Content-Type" => "application/json", "Accept" => "#{STREAM}, application/json" }
  end

  test "after the admin step the wizard asks for a passkey, and adding one shows the codes then goes on to site" do
    walk_to_passkey_step
    assert_redirected_to setup_step_path("passkey")

    get setup_step_path("passkey")
    assert_response :success
    assert_select "nav[aria-label='Setup steps'] li[aria-current=step]", text: /Passkey/
    assert_select "#setup-passkey h1", text: /\A#{I18n.t("setup.passkey.title")}\b/
    assert_select "#setup-passkey p", text: I18n.t("setup.passkey.lead")
    assert_select "#setup-passkey #{REGISTER}" do |forms|
      form = forms.first
      assert_equal "patch", form["data-admin--passkeys--register-method-value"]
      assert_equal setup_step_path("passkey"), form["data-admin--passkeys--register-create-url-value"]
      assert_equal setup_passkey_options_path, form["data-admin--passkeys--register-options-url-value"]
      assert_nil form["data-admin--passkeys--register-admin--passkeys--confirm-outlet"], "the wizard is not gated by Confirm it's you"
      messages = JSON.parse(form["data-messages"])
      assert_equal I18n.t("admin.components.account_screen.passkey_dialog.name_blank"), messages["components.account_screen.passkey_dialog.name_blank"]
      assert_equal I18n.t("admin.components.account_screen.passkey_dialog.failed"), messages["components.account_screen.passkey_dialog.failed"]
    end
    assert_select "#setup-passkey label", text: I18n.t("setup.passkey.name")
    assert_select "#setup-passkey p", text: I18n.t("setup.passkey.name_help")
    assert_select "#setup-passkey button[type=submit][data-admin--passkeys--register-target=add]", text: I18n.t("setup.passkey.add")
    assert_select "#setup-passkey p[hidden][data-admin--passkeys--register-target=unsupported]", text: I18n.t("setup.passkey.unsupported")
    assert_select "head meta[name=turbo-cache-control][content=no-cache]"
    assert_select "head script[type=importmap]", text: /"admin"/

    add_passkey_in_wizard

    assert_response :success
    assert_equal STREAM, response.media_type
    assert_select "turbo-stream[action=replace][target=setup-passkey] template" do
      assert_select "#setup-passkey h1", text: I18n.t("admin.components.ui.recovery_codes.title")
      assert_select "a[data-admin--ui--recovery-codes-target=done][href=?]", setup_step_path("site")
    end
    codes = css_select("turbo-stream[target=setup-passkey] template pre").text.split
    assert_equal RecoveryCode::COUNT, codes.size
    assert_equal codes.map { |code| RecoveryCode.digest(code) }.sort, owner.recovery_codes.unused.pluck(:digest).sort
    assert_equal [ "MacBook" ], owner.passkeys.pluck(:name)
    event = Audit::Event.find_by!(action: "passkey.added")
    assert_equal [ "setup", "User", owner.id ], [ event.channel, event.actor_type, event.actor_id ]

    get setup_step_path("site")
    assert_response :success
    get setup_step_path("passkey")
    assert_redirected_to setup_step_path("site"), "a founding owner who holds a passkey is sent on"
  end

  test "with production's default policy there is no Skip for now, and site is sent back to the passkey step" do
    assert_equal "owners_and_admins", site_settings(:default).effective_passkey_policy(production: true)
    walk_to_passkey_step(policy: "owners_and_admins")
    assert Session.find_by!(user: owner).enrolment_due?, "the founding owner's session is held, as in production"

    get setup_step_path("passkey")
    assert_response :success
    assert_select "a", text: I18n.t("setup.passkey.skip"), count: 0
    assert_select "nav[aria-label='Setup steps'] li", text: /Passkey/ do
      assert_select "span", text: I18n.t("setup.layout.optional"), count: 0
    end

    LATER_STEPS.each do |step|
      get setup_step_path(step)
      assert_redirected_to setup_step_path("passkey"), "#{step} waits for the passkey"
      patch setup_step_path(step)
      assert_redirected_to setup_step_path("passkey"), "#{step}'s write waits for the passkey"
    end
    %w[token admin].each do |step|
      get setup_step_path(step)
      assert_redirected_to setup_step_path("passkey")
    end
    get setup_path
    assert_redirected_to setup_step_path("passkey")
    assert_not ApiToken.exists?(user: owner), "no MCP token is issued before the passkey"
    assert Setup.required?

    add_passkey_in_wizard
    assert_response :success
    assert_not Session.find_by!(user: owner).enrolment_due?

    get setup_step_path("site")
    assert_response :success
  end

  test "with nobody the step is optional and Skip for now goes on" do
    walk_to_passkey_step(policy: "nobody")

    get setup_step_path("passkey")
    assert_response :success
    assert_select "#setup-passkey a[href=?]", setup_step_path("site"), text: I18n.t("setup.passkey.skip")
    assert_select "nav[aria-label='Setup steps'] li", text: /Passkey\s+Optional/
    assert_select "#setup-passkey h1", text: /Optional/
    assert_select "#setup-passkey a", text: I18n.t("setup.back.label"), count: 0

    get setup_step_path("site")
    assert_response :success
    assert_not owner.passkeys.exists?
  end

  test "the step's endpoints are reachable while setup is pending" do
    walk_to_passkey_step(policy: "owners_and_admins")
    assert Setup.required?

    post setup_passkey_options_path, as: :json
    assert_response :success
    assert_equal owner.webauthn_id, response.parsed_body.dig("user", "id")
    assert response.parsed_body["challenge"].present?

    patch setup_step_path("passkey"), params: { credential: "{}", name: "MacBook" }.to_json,
      headers: { "Content-Type" => "application/json", "Accept" => "#{STREAM}, application/json" }
    assert_response :unprocessable_entity
    assert_equal SignIn::Passkeys::Add.failed, response.parsed_body["error"]
    assert_not owner.passkeys.exists?

    delete admin_sign_out_path
    post setup_passkey_options_path, as: :json
    assert_response :not_found, "the options are the signed-in owner's alone"
  end

  # The step adds a first passkey, unconfirmed because the session is the
  # password just set; an owner who holds one is past it, and a further one
  # is added from Your account, behind Confirm it's you.
  test "an owner who holds a passkey gets no options and no add from the step" do
    walk_to_passkey_step
    client = fake_authenticator
    add_passkey_in_wizard(client: client)
    assert_response :success
    assert_equal 1, owner.passkeys.count

    post setup_passkey_options_path, as: :json
    assert_response :not_found

    credential = client.create(challenge: WebAuthn.standard_encoder.encode(SecureRandom.random_bytes(32)), rp_id: "localhost", user_verified: true).to_json
    patch setup_step_path("passkey"), params: { credential: credential, name: "Second" }.to_json,
      headers: { "Content-Type" => "application/json", "Accept" => "#{STREAM}, application/json" }
    assert_response :not_found
    assert_equal [ "MacBook" ], owner.passkeys.pluck(:name)
  end

  # The challenge is in a cookie of its own: a page of the wizard sent with
  # the session cookie from before the options (another tab's load of a
  # wizard page, a prefetch of a wizard link), answered after them, writes
  # the session back as it read it, and the challenge is still there for
  # the add.
  test "a request that writes the session back after the options leaves the challenge alone" do
    walk_to_passkey_step
    session_key = Rails.application.config.session_options.fetch(:key)
    before_options = cookies[session_key]

    post setup_passkey_options_path, as: :json
    options = response.parsed_body
    cookies[session_key] = before_options
    get setup_step_path("passkey")
    assert_response :success
    assert Array(response.headers["Set-Cookie"]).join("\n").include?("#{session_key}="), "the page wrote the session cookie back"

    credential = fake_authenticator.create(challenge: options.fetch("challenge"), rp_id: options.dig("rp", "id"), user_verified: true).to_json
    patch setup_step_path("passkey"), params: { credential: credential, name: "MacBook" }.to_json,
      headers: { "Content-Type" => "application/json", "Accept" => "#{STREAM}, application/json" }
    assert_response :success
    assert_equal [ "MacBook" ], owner.passkeys.pluck(:name)
  end

  test "the options are gone once setup is complete" do
    sign_in_as(users(:one))

    post setup_passkey_options_path, as: :json

    assert_response :not_found
  end

  test "at an IP address no passkey can be made: the step says why and goes on, whatever the policy" do
    host! "127.0.0.1"
    walk_to_passkey_step(policy: "owners_and_admins")

    get setup_step_path("passkey")
    assert_response :success
    assert_select "#setup-passkey p", text: I18n.t("setup.passkey.unavailable")
    assert_select "#setup-passkey a[href=?]", setup_step_path("site"), text: I18n.t("setup.passkey.continue")
    assert_select REGISTER, count: 0
    assert_select "nav[aria-label='Setup steps'] li", text: /Passkey\s+Optional/

    post setup_passkey_options_path, as: :json
    assert_response :not_found
    get setup_step_path("site")
    assert_response :success
  end
end
