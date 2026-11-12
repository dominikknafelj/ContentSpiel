require "test_helper"

# Enrolment through the real controllers: a person the passkey policy covers
# who holds no passkey is sent to add one at sign-in, and CS Studio and the
# preview stay closed to them until they have; the policy is read when a
# session starts, so a session open when it changes carries on.
class PasskeyEnrolmentTest < ActionDispatch::IntegrationTest
  EMAIL = "ann@example.org".freeze
  PASSWORD = "password12345".freeze
  STREAM = "text/vnd.turbo-stream.html".freeze

  setup do
    freeze_time
    @site = site_settings(:default)
    @site.update!(setup_completed_at: Time.current, passkey_policy: "everyone")
    @user = User.create!(email_address: EMAIL, password: PASSWORD)
  end

  def sign_in_with_password(email = EMAIL)
    post admin_sign_in_path, params: { email_address: email, password: PASSWORD }
    travel 20.seconds
  end

  def registration_options
    post admin_account_passkey_options_path, as: :json
    assert_response :success
    response.parsed_body
  end

  def add_from_enrolment(client: fake_authenticator, name: "MacBook")
    options = registration_options
    credential = client.create(challenge: options.fetch("challenge"), rp_id: options.dig("rp", "id"), user_verified: true).to_json
    post admin_account_passkeys_path, params: { credential: credential, name: name, from: "enrolment" }.to_json,
      headers: { "Content-Type" => "application/json", "Accept" => "#{STREAM}, application/json" }
  end

  test "a covered person without a passkey is sent to enrolment from every CS Studio page and the preview, and Sign out still works" do
    sign_in_with_password
    assert Session.find_by!(user: @user).enrolment_due?

    [ admin_root_path, admin_settings_path, admin_account_path, admin_pages_path, "/preview/draft" ].each do |path|
      get path
      assert_redirected_to admin_enrolment_path, "#{path} is closed until a passkey is added"
    end

    get admin_enrolment_path
    assert_response :success
    assert_select "#enrolment h1", text: I18n.t("admin.enrolment.show.title")
    assert_select "#enrolment p", text: I18n.t("admin.enrolment.show.lead.everyone")
    assert_select "#enrolment [data-controller~='admin--passkeys--register'][data-admin--passkeys--register-from-value=enrolment]"
    assert_select "#enrolment label", text: I18n.t("admin.enrolment.show.name")
    assert_select "#enrolment p", text: I18n.t("admin.enrolment.show.name_help")
    assert_select "#enrolment button[type=submit]", text: I18n.t("admin.enrolment.show.add")
    assert_select "#confirm-identity"
    assert_select "head meta[name=turbo-cache-control][content=no-cache]"
    assert_select "head script[type=importmap]", text: /"admin"/
    messages = JSON.parse(css_select("[data-controller~='admin--passkeys--register']").first["data-messages"])
    assert_equal I18n.t("admin.components.account_screen.passkey_dialog.name_blank"), messages["components.account_screen.passkey_dialog.name_blank"]
    assert_equal I18n.t("admin.components.account_screen.passkey_dialog.failed"), messages["components.account_screen.passkey_dialog.failed"]

    patch admin_account_profile_path, params: { user: { name: "Ann" } }
    assert_response :forbidden, "a write is refused, not redirected"
    assert_not_equal "Ann", @user.reload.name
    get admin_jump_path(q: "x"), as: :json
    assert_response :forbidden

    get admin_enrolment_path
    assert_select "form[action='#{admin_sign_out_path}'] button", text: I18n.t("admin.enrolment.show.sign_out")
    delete admin_sign_out_path
    assert_redirected_to admin_sign_in_path
    assert_not Session.exists?(user: @user)
  end

  test "a Turbo visit while enrolment is due is answered with a page Turbo loads whole" do
    sign_in_with_password

    get admin_pages_path, headers: { "X-Turbo-Request-Id" => SecureRandom.uuid }

    assert_response :success
    assert_select "meta[name=turbo-visit-control][content=reload]"
    get admin_settings_path, headers: { "Turbo-Frame" => "content" }
    assert_select "meta[name=turbo-visit-control][content=reload]"
  end

  test "a policy saved while a covered person is signed in leaves that session alone; their next sign-in is sent to enrolment" do
    @site.update!(passkey_policy: "nobody")
    sign_in_with_password
    get admin_pages_path
    assert_response :redirect
    assert_not_equal admin_enrolment_path, URI(response.location).path

    as_owner = Current.set(actor: users(:one), channel: :admin) { Settings::Save.call(@site.reload, attributes: { passkey_policy: "everyone" }) }
    assert as_owner.ok?, as_owner.errors.inspect

    get admin_account_path
    assert_response :success, "the open session carries on"

    delete admin_sign_out_path
    sign_in_with_password
    get admin_account_path
    assert_redirected_to admin_enrolment_path
  end

  test "adding the passkey on the enrolment page shows the codes, and Done goes where the person was going" do
    sign_in_with_password
    get admin_account_path
    assert_redirected_to admin_enrolment_path

    add_from_enrolment

    assert_response :success
    assert_equal STREAM, response.media_type
    assert_select "turbo-stream[action=replace][target=enrolment] template" do
      assert_select "#enrolment h1", text: I18n.t("admin.components.ui.recovery_codes.title")
      assert_select "a[data-admin--ui--recovery-codes-target=done][href=?]", admin_account_url
    end
    codes = css_select("turbo-stream[target=enrolment] template pre").text.split
    assert_equal RecoveryCode::COUNT, codes.size
    assert_equal codes.map { |code| RecoveryCode.digest(code) }.sort, @user.recovery_codes.unused.pluck(:digest).sort
    assert_not Session.find_by!(user: @user).enrolment_due?

    get admin_account_path
    assert_response :success, "CS Studio is open once the passkey is added"
    get admin_enrolment_path
    assert_redirected_to admin_root_path
  end

  test "a person who still holds codes is sent straight on after adding the passkey" do
    texts = RecoveryCode.texts
    texts.each { |text| @user.recovery_codes.create!(digest: RecoveryCode.digest(text), generated_at: 1.day.ago) }
    sign_in_with_password
    # Codes alone are a second factor: the password is followed by one.
    post admin_second_factor_code_path, params: { recovery_code: texts.first }
    get admin_pages_path
    assert_redirected_to admin_enrolment_path

    add_from_enrolment

    assert_redirected_to admin_pages_url
    assert_equal 303, response.status
    assert_equal 1, @user.passkeys.count
  end

  test "a person the policy does not cover, or who has a passkey, is sent on from the enrolment page" do
    @site.update!(passkey_policy: "nobody")
    sign_in_with_password

    get admin_enrolment_path

    assert_redirected_to admin_root_path
  end

  test "the lead names the policy" do
    @site.update!(passkey_policy: "owners_and_admins")
    owner = users(:one)
    owner.update!(password: PASSWORD)
    sign_in_with_password(owner.email_address)

    get admin_enrolment_path

    assert_select "#enrolment p", text: I18n.t("admin.enrolment.show.lead.owners_and_admins")
  end
end
