require "test_helper"

# The second step of a sign-in, through the real controllers: a right
# password for an account that holds a passkey or recovery codes is held
# in `cs_second_factor` for five minutes, and only a passkey of the
# account's own or one of its unused codes finishes it. Every proof is
# counted in the account's bucket as the password was (`SignIn::Proof`),
# and nothing of a whole sign-in (a session, the known-device cookie) is
# written before the proof.
class SecondFactorTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  EMAIL = "ann@example.org".freeze
  PASSWORD = "password12345".freeze
  ADDRESS = "127.0.0.1".freeze
  COOKIE = Admin::SecondFactorsController::SECOND_FACTOR_COOKIE.to_s

  setup do
    freeze_time
    site_settings(:default).update!(setup_completed_at: Time.current)
    @user = User.create!(email_address: EMAIL, password: PASSWORD)
    @codes = RecoveryCode.texts
    @codes.each { |code| @user.recovery_codes.create!(digest: RecoveryCode.digest(code), generated_at: Time.current) }
    @written = []
  end

  # Every Set-Cookie a request answers is kept, so a test can say a cookie
  # was never written, not only that it is not held now.
  def keep_cookies
    @written.concat(Array(response.headers["Set-Cookie"]).flat_map { |line| line.split("\n") })
  end

  def written?(name) = @written.any? { |line| line.start_with?("#{name}=") && !line.start_with?("#{name}=;") }

  def password_step(password: PASSWORD)
    post admin_sign_in_path, params: { email_address: EMAIL, password: password }
    keep_cookies
  end

  def send_code(code)
    post admin_second_factor_code_path, params: { recovery_code: code }
    keep_cookies
  end

  def options
    post admin_second_factor_options_path, as: :json
    keep_cookies
    assert_response :success
    response.parsed_body
  end

  def send_passkey(credential)
    post admin_second_factor_passkey_path, params: { credential: credential }, as: :json
    keep_cookies
    assert_response :success
    response.parsed_body.fetch("location")
  end

  def count_of(counter)
    digest = counter == :account ? VisitorAddress.digest(EMAIL, purpose: SignIn::Throttle::KEY_PURPOSE) : VisitorAddress.key(ADDRESS, purpose: SignIn::Throttle::KEY_PURPOSE)
    SignIn.store.read("sign_in:studio:#{counter}:#{digest}").to_i
  end

  # The step's cookie holding `value`, encrypted as the controller writes it.
  def plant_step(value)
    jar = ActionDispatch::TestRequest.create.cookie_jar
    jar.encrypted[COOKIE] = { value: value }
    cookies[COOKIE] = jar[COOKIE]
  end

  def assert_plain_sign_in(alert: nil)
    assert_redirected_to admin_sign_in_path
    alert ? assert_equal(alert, flash[:alert]) : assert_nil(flash[:alert])
    assert cookies[COOKIE].blank?, "the step's cookie is gone"
    assert_equal 0, Session.count
    follow_redirect!
  end

  test "a right password for an account with a passkey goes to the second step and starts no session" do
    add_passkey(@user, client: fake_authenticator)

    password_step

    assert_redirected_to admin_second_factor_path
    assert_equal 0, Session.count
    assert_not written?("session_id")
    assert_not written?(Admin::SignInCompletion::DEVICE_COOKIE)
    assert written?(COOKIE)
    assert_equal 0, Audit::Event.where(action: "session.created").count
    get admin_root_path
    assert_redirected_to admin_sign_in_path

    get admin_second_factor_path
    assert_response :success
    assert_select "h1", text: I18n.t("admin.second_factor.show.title")
    assert_select "p", text: I18n.t("admin.second_factor.show.lead", email: EMAIL)
    assert_select "[data-controller~='passkey-sign-in'] button[data-passkey-sign-in-target=button][hidden]", text: I18n.t("admin.second_factor.show.use_passkey")
    assert_select "a[href='#{admin_second_factor_path(with: "code")}']", text: I18n.t("admin.second_factor.show.use_code")
    assert_select "input[name=recovery_code]", count: 0
    assert_select "form[action='#{admin_second_factor_path}'] button", text: I18n.t("admin.second_factor.show.start_over")
  end

  test "an account with codes and no passkey opens on the code view" do
    password_step

    assert_redirected_to admin_second_factor_path(with: "code")
    follow_redirect!
    assert_select "label[for=recovery_code]", text: I18n.t("admin.second_factor.show.code")
    assert_select "input[name=recovery_code][autocomplete='one-time-code'][aria-describedby=recovery-code-help]"
    assert_select "#recovery-code-help", text: I18n.t("admin.second_factor.show.code_help")
    assert_select "form[action='#{admin_second_factor_code_path}'] button[type=submit]", text: I18n.t("admin.second_factor.show.submit_code")
    assert_select "[data-controller~='passkey-sign-in']", count: 0
    assert_select "form[action='#{admin_second_factor_path}'] button", text: I18n.t("admin.second_factor.show.start_over")

    get admin_second_factor_path
    assert_select "input[name=recovery_code]", 1, "with no passkey the code view is the only one"
    assert_select "a[href='#{admin_second_factor_path}']", count: 0
  end

  test "the code view of an account with a passkey links back to the passkey view beside Start over" do
    add_passkey(@user, client: fake_authenticator)
    password_step

    get admin_second_factor_path(with: "code")

    assert_select "input[name=recovery_code]", 1
    assert_select "a[href='#{admin_second_factor_path}']", text: I18n.t("admin.second_factor.show.use_passkey")
    assert_select "div:has(> a[href='#{admin_second_factor_path}']) > form[action='#{admin_second_factor_path}'] button",
      text: I18n.t("admin.second_factor.show.start_over")
  end

  test "a right code signs in, uses the code, records recovery_code.used with what is left, queues the mail and lands on Your account's passkeys" do
    password_step

    with_mail_state(:working) { send_code(@codes.third.downcase.delete("-")) }

    mail = enqueued_jobs.map { |job| ActiveJob::Arguments.deserialize(job["arguments"]) }
      .find { |arguments| arguments.first(2) == %w[SignInMailer recovery_code_used] }
    assert mail, "the account's mail is queued"
    assert_equal [ @user, { used_at: Time.current, from_address: ADDRESS, left: 9, origin: "http://www.example.com" } ], mail.last[:args]

    assert_redirected_to admin_account_path(anchor: "passkeys")
    assert_equal 9, flash[:recovery_code_left]
    session = Session.sole
    assert_equal @user, session.user
    assert_equal "recovery_code", session.authenticated_with
    assert cookies[COOKIE].blank?
    assert written?(Admin::SignInCompletion::DEVICE_COOKIE)
    assert_equal({ "method" => "recovery_code" }, Audit::Event.where(action: "session.created").sole.metadata)
    used = Audit::Event.where(action: "recovery_code.used").sole
    assert_equal({ "left" => 9 }, used.metadata)
    assert_equal [ @user.id, @user.id ], [ used.user_id, used.subject_id ]
    assert_equal 9, @user.recovery_codes.unused.count

    get admin_account_path
    assert_response :success
  end

  test "a wrong code and a used code get the same sentence" do
    @user.recovery_codes.redeem(@codes.first)
    password_step

    send_code(@codes.first)
    assert_redirected_to admin_second_factor_path(with: "code")
    used = flash[:alert]
    send_code("0000-0000")
    assert_equal used, flash[:alert]
    assert_equal I18n.t("admin.second_factor.code_failed"), used
    assert_equal 0, Session.count

    events = Audit::Event.where(action: "session.second_factor_failed").order(:id)
    assert_equal 2, events.count, "each failure is its own event, never coalesced into one"
    events.each do |event|
      assert_nil event.user_id
      assert_equal @user.id, event.subject_id
      assert_equal({ "method" => "recovery_code" }, event.metadata)
    end
  end

  test "a right password then five wrong codes closes the account, and no session or known-device cookie was ever written" do
    add_passkey(@user, client: fake_authenticator)
    password_step
    assert_equal 1, count_of(:account), "the password's count stands"

    4.times { send_code("0000-0000") }
    assert_equal I18n.t("admin.second_factor.code_failed"), flash[:alert]
    locked = Audit::Event.where(action: "session.locked").sole
    assert_equal({ "bucket" => "account", "email_address" => EMAIL, "level" => 0, "seconds" => 60 }, locked.metadata)

    send_code("0000-0000")
    assert_redirected_to admin_second_factor_path(with: "code")
    assert_equal I18n.t("admin.sessions.locked"), flash[:alert]
    send_code(@codes.first)
    assert_equal I18n.t("admin.sessions.locked"), flash[:alert], "the right code meets the lock too"
    assert_equal 10, @user.recovery_codes.unused.count

    password_step
    assert_redirected_to admin_sign_in_path
    assert_equal I18n.t("admin.sessions.locked"), flash[:alert], "and so does the right password"

    assert_equal 0, Session.count
    assert_not written?("session_id")
    assert_not written?(Admin::SignInCompletion::DEVICE_COOKIE)
    assert_equal 4, Audit::Event.where(action: "session.second_factor_failed").count
  end

  test "after five minutes the step says it took too long and the password must be typed again" do
    password_step
    travel SignIn::SECOND_STEP_LIFETIME + 1.second

    send_code(@codes.first)

    assert_plain_sign_in(alert: I18n.t("admin.sessions.second_factor_expired"))
    assert_equal 10, @user.recovery_codes.unused.count
    get admin_second_factor_path
    assert_plain_sign_in

    password_step
    send_code(@codes.first)
    assert_redirected_to admin_account_path(anchor: "passkeys")
  end

  test "a tampered cookie and one naming a deleted user are a plain sign-in" do
    get admin_second_factor_path
    assert_plain_sign_in

    cookies[COOKIE] = "not what the server wrote"
    get admin_second_factor_path
    assert_plain_sign_in

    plant_step({ "user_id" => User.maximum(:id) + 1, "at" => Time.current.to_i })
    send_code(@codes.first)
    assert_plain_sign_in(alert: I18n.t("admin.sessions.second_factor_expired"))

    password_step
    @user.destroy!
    get admin_second_factor_path
    assert_plain_sign_in(alert: I18n.t("admin.sessions.second_factor_expired"))
    post admin_second_factor_options_path, as: :json
    assert_response :not_found
  end

  test "Start over forgets the step" do
    password_step

    delete admin_second_factor_path

    assert_redirected_to admin_sign_in_path
    assert_response :see_other
    assert cookies[COOKIE].blank?
    send_code(@codes.first)
    assert_plain_sign_in
    assert_equal 10, @user.recovery_codes.unused.count
  end

  test "a passkey finishes the step; another user's passkey is refused with passkey_failed" do
    client = fake_authenticator
    passkey = add_passkey(@user, client: client)
    other = User.create!(email_address: "bea@example.org", password: PASSWORD)
    stranger = fake_authenticator
    other_passkey = add_passkey(other, client: stranger, name: "Bea's")
    password_step

    offered = options
    assert_equal [ passkey.external_id ], offered.fetch("allowCredentials").map { |credential| credential.fetch("id") },
      "the account's own passkeys alone are offered"
    location = send_passkey(passkey_assertion(stranger, challenge: offered.fetch("challenge"), user_handle: other.webauthn_id))
    assert_equal admin_second_factor_path, location
    assert_equal I18n.t("admin.second_factor.passkey_failed"), flash[:alert]
    assert_equal 0, Session.count
    assert_nil other_passkey.reload.last_used_at
    assert_equal({ "method" => "passkey" }, Audit::Event.where(action: "session.second_factor_failed").sole.metadata)

    @user.recovery_codes.delete_all
    send_passkey(passkey_assertion(stranger, challenge: options.fetch("challenge"), user_handle: other.webauthn_id))
    assert_equal I18n.t("admin.second_factor.passkey_failed_no_codes"), flash[:alert]

    location = send_passkey(passkey_assertion(client, challenge: options.fetch("challenge"), user_handle: @user.webauthn_id))
    assert_equal admin_root_url, location
    assert_equal "passkey", Session.sole.authenticated_with
    assert cookies[COOKIE].blank?
    assert_not_nil passkey.reload.last_used_at
    assert_equal({ "method" => "passkey" }, Audit::Event.where(action: "session.created").sole.metadata)
  end

  test "after a whole sign-in the account's run is clear and the address's wide count is one" do
    password_step(password: "wrong")
    password_step
    assert_equal 2, count_of(:account)
    assert_equal 1, count_of(:wide), "the right password gave its address count back"

    send_code(@codes.first)

    assert_redirected_to admin_account_path(anchor: "passkeys")
    assert_equal 0, count_of(:account), "the run is forgotten"
    assert_equal 1, count_of(:wide), "the whole sign-in cost the address nothing; the wrong password's count stands"
  end
end
