require "test_helper"

# The Passkeys card's actions, through the real endpoints: the registration
# options and the add behind Confirm it's you, a rename without it, a remove
# behind it, each on the signed-in person's own passkeys only. The gate
# (`Admin::RecentConfirmation`) is held here through the four actions it
# guards, this controller's three and the recovery codes'.
class Admin::PasskeysControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  STREAM = "text/vnd.turbo-stream.html".freeze
  WORDS = "admin.components.account_screen".freeze

  setup do
    freeze_time
    site_settings(:default).update!(setup_completed_at: Time.current)
    @user = users(:reader)
    sign_in_as @user
    @session = Current.session
    @client = fake_authenticator
  end

  def registration_options
    post admin_account_passkey_options_path, as: :json
    assert_response :success
    response.parsed_body
  end

  # What the register script sends: the browser's credential as JSON and the
  # typed name, asking for a stream with JSON beside it.
  def add(name: "MacBook", client: @client, options: registration_options)
    credential = client.create(challenge: options.fetch("challenge"), rp_id: options.dig("rp", "id"), user_verified: true).to_json
    post admin_account_passkeys_path, params: { credential: credential, name: name }.to_json,
      headers: { "Content-Type" => "application/json", "Accept" => "#{STREAM}, application/json" }
  end

  def outside_the_window = travel(Session::CONFIRM_WINDOW + 1.minute)

  test "adding the first passkey answers the card, the toast and the codes, and a second answers no codes" do
    offered = registration_options
    assert_equal "required", offered.dig("authenticatorSelection", "residentKey")
    assert_equal [], offered.fetch("excludeCredentials")
    assert_equal @user.reload.webauthn_id, offered.dig("user", "id")

    add(options: offered)

    assert_response :ok
    assert_equal STREAM, response.media_type
    passkey = @user.passkeys.sole
    assert_equal "MacBook", passkey.name
    assert_select "turbo-stream[action=replace][target=account-passkeys] template", text: /MacBook/
    assert_select "turbo-stream[action=replace][target=account-recovery] template", text: /10 of 10 codes left/
    assert_select "turbo-stream[action=replace][target=confirm-identity] template", text: /Use your passkey/
    assert_select "turbo-stream[action=append][target=toasts] template", text: /Passkey added\./
    assert_select "turbo-stream[action=update][target=account-recovery-codes] template dialog[data-admin--ui--dialog-open-on-load]"
    assert_select "turbo-stream[action=append][targets=head] template meta#recovery-codes-no-cache[name=turbo-cache-control][content=no-cache]"
    streams = css_select("turbo-stream").map { |stream| stream["targets"] || stream["target"] }
    assert_operator streams.index("head"), :<, streams.index("account-recovery-codes"), "the page is uncacheable before it holds the codes"
    codes = css_select("turbo-stream[target=account-recovery-codes] template pre").text.split
    assert_equal RecoveryCode::COUNT, codes.size
    assert codes.all? { |code| code.match?(/\A[0-9A-Z]{4}-[0-9A-Z]{4}\z/) }
    assert_equal codes.map { |code| RecoveryCode.digest(code) }.sort, @user.recovery_codes.unused.pluck(:digest).sort,
      "the codes shown are the codes stored"

    second = fake_authenticator
    again = registration_options
    assert_equal [ passkey.external_id ], again.fetch("excludeCredentials").map { |credential| credential.fetch("id") },
      "an authenticator that holds one already is told so"
    add(name: "Phone", client: second, options: again)

    assert_response :ok
    assert_equal 2, @user.passkeys.count
    assert_select "turbo-stream[action=replace][target=account-passkeys] template", text: /2 passkeys/
    assert_select "turbo-stream[target=account-recovery-codes]", count: 0
    assert_select "meta[name=turbo-cache-control]", count: 0
  end

  test "a refused registration answers 422 with the sentence and stores nothing" do
    offered = registration_options
    add(options: offered.merge("challenge" => WebAuthn.standard_encoder.encode(SecureRandom.random_bytes(32))))

    assert_response :unprocessable_entity
    assert_equal({ "error" => I18n.t("admin.passkeys.add.failed") }, response.parsed_body)
    assert_empty @user.passkeys
    assert_equal 0, RecoveryCode.where(user: @user).count
  end

  test "a blank name is refused with the model's sentence" do
    add(name: "  ")

    assert_response :unprocessable_entity
    assert_kind_of String, response.parsed_body.fetch("error")
    assert_empty @user.passkeys
  end

  test "the four gated actions outside the window write nothing and answer 403 with the confirm marker, as JSON and as a stream" do
    passkey = add_passkey(@user, client: @client)
    other = add_passkey(@user, client: fake_authenticator, name: "Phone")
    outside_the_window

    post admin_account_passkey_options_path, as: :json
    assert_response :forbidden
    assert_equal({ "confirm" => true }, response.parsed_body)
    assert_equal "required", response.headers[Admin::RecentConfirmation::CONFIRM_HEADER]
    assert_nil cookies["#{PasskeyChallenges::COOKIE_PREFIX}register"].presence, "no challenge is issued"

    post admin_account_passkeys_path, params: { credential: "{}", name: "Third" }.to_json,
      headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
    assert_response :forbidden
    assert_equal({ "confirm" => true }, response.parsed_body)
    assert_equal "required", response.headers[Admin::RecentConfirmation::CONFIRM_HEADER]

    [ -> { delete admin_account_passkey_path(other), headers: { "Accept" => STREAM } },
      -> { post admin_account_recovery_codes_path, headers: { "Accept" => STREAM } } ].each do |request|
      request.call
      assert_response :forbidden
      assert_equal STREAM, response.media_type
      assert_equal "required", response.headers[Admin::RecentConfirmation::CONFIRM_HEADER]
      assert_select "turbo-stream[action=append][target=#{Admin::Ui::ConfirmIdentityDialogComponent::REQUESTS_ID}] template [data-admin--passkeys--confirm-target=request]"
    end

    assert_equal [ passkey, other ].map(&:id).sort, @user.passkeys.ids.sort
    assert_empty @user.recovery_codes
    assert_empty Audit::Event.where(action: %w[passkey.added passkey.removed recovery_codes.generated])
  end

  test "renaming needs no confirmation" do
    passkey = add_passkey(@user, client: @client)
    outside_the_window

    patch admin_account_passkey_path(passkey), params: { name: "Work laptop" }, headers: { "Accept" => STREAM }

    assert_response :ok
    assert_equal "Work laptop", passkey.reload.name
    assert_select "turbo-stream[action=replace][target=account-passkeys] template", text: /Work laptop/
    assert_select "turbo-stream[action=append][target=toasts] template", text: /Passkey renamed\./
    assert_equal "passkey.renamed", Audit::Event.last.action
  end

  test "a refused rename redraws the dialog's fields with the sentence, 422" do
    passkey = add_passkey(@user, client: @client)

    patch admin_account_passkey_path(passkey), params: { name: "x" * (Passkey::NAME_LIMIT + 1) }, headers: { "Accept" => STREAM }

    assert_response :unprocessable_entity
    assert_select "turbo-stream[action=replace][target=passkey-#{passkey.id}-rename-fields] template [id=passkey-#{passkey.id}-rename-errors] p"
    assert_select "turbo-stream[target=account-passkeys]", count: 0
    assert_equal "1Password", passkey.reload.name
  end

  test "removing one asks nothing more inside the window, and lands on the card with Passkey removed." do
    passkey = add_passkey(@user, client: @client)
    add_passkey(@user, client: fake_authenticator, name: "Phone")

    delete admin_account_passkey_path(passkey), headers: { "Accept" => "#{STREAM}, text/html" }

    assert_redirected_to admin_account_path(anchor: "passkeys")
    assert_response :see_other
    assert_equal I18n.t("admin.accounts.passkeys.removed"), flash[:notice]
    assert_not Passkey.exists?(passkey.id)
  end

  test "another user's passkey is not found" do
    theirs = add_passkey(users(:author), client: fake_authenticator)

    patch admin_account_passkey_path(theirs), params: { name: "Mine now" }, headers: { "Accept" => STREAM }
    assert_response :not_found
    delete admin_account_passkey_path(theirs), headers: { "Accept" => STREAM }
    assert_response :not_found

    assert_equal "1Password", theirs.reload.name
  end

  test "a crafted DELETE of a covered person's last passkey is refused and the passkey stays" do
    site_settings(:default).update!(passkey_policy: "everyone")
    passkey = add_passkey(@user, client: @client)

    delete admin_account_passkey_path(passkey), headers: { "Accept" => STREAM }

    assert_response :unprocessable_entity
    assert_select "turbo-stream[action=append][target=toasts] template", text: /#{Regexp.escape(I18n.t("#{WORDS}.passkeys_card.last_required"))}/
    assert Passkey.exists?(passkey.id)
    assert_empty Audit::Event.where(action: "passkey.removed")
  end

  test "an uncovered person's last passkey goes with the recovery codes" do
    passkey = add_passkey(@user, client: @client)
    SignIn::RecoveryCodes::Generate.call(@user, actor: @user)

    delete admin_account_passkey_path(passkey), headers: { "Accept" => STREAM }

    assert_response :see_other
    assert_not Passkey.exists?(passkey.id)
    assert_equal 0, RecoveryCode.where(user: @user).count
  end
end
