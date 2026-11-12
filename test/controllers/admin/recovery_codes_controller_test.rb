require "test_helper"

# Generate… and Regenerate… on the Recovery codes card: behind Confirm it's
# you (the gate's refusal is held with the other three actions in
# `Admin::PasskeysControllerTest`), a new set of ten, answered as a stream
# that redraws the card and shows the codes once, on a page Turbo keeps no
# snapshot of.
class Admin::RecoveryCodesControllerTest < ActionDispatch::IntegrationTest
  STREAM = "text/vnd.turbo-stream.html".freeze

  setup do
    freeze_time
    site_settings(:default).update!(setup_completed_at: Time.current)
    @user = users(:reader)
    sign_in_as @user
    add_passkey(@user, client: fake_authenticator)
  end

  def generate = post(admin_account_recovery_codes_path, headers: { "Accept" => STREAM })

  def shown = css_select("turbo-stream[target=account-recovery-codes] template pre").text.split

  test "Generate makes ten codes and shows them once" do
    generate

    assert_response :ok
    assert_equal STREAM, response.media_type
    assert_equal RecoveryCode::COUNT, shown.size
    assert shown.all? { |code| code.match?(/\A[0-9A-Z]{4}-[0-9A-Z]{4}\z/) }
    assert_select "turbo-stream[action=replace][target=account-recovery] template", text: /10 of 10 codes left/
    assert_select "turbo-stream[action=update][target=account-recovery-codes] template dialog[data-admin--ui--dialog-open-on-load]"
    assert_select "turbo-stream[action=append][targets=head] template meta#recovery-codes-no-cache[name=turbo-cache-control][content=no-cache]"
    assert_equal({ "count" => 10, "replaced" => 0 }, Audit::Event.where(action: "recovery_codes.generated").sole.metadata)
    assert_no_match(/#{shown.first}/, Audit::Event.last.to_json, "no code reaches the log")
  end

  test "Regenerate replaces the old set: the codes shown before stop working" do
    generate
    before = shown
    @user.recovery_codes.unused.first.update_column(:used_at, Time.current)

    generate

    assert_equal RecoveryCode::COUNT, @user.recovery_codes.unused.count
    assert_empty before & shown
    assert_not @user.recovery_codes.redeem(before.last)
    assert_equal 9, Audit::Event.where(action: "recovery_codes.generated").order(:id).last.metadata["replaced"]
  end

  test "without a passkey Generate is refused with a toast and makes no codes" do
    @user.passkeys.delete_all

    generate

    assert_response :unprocessable_entity
    assert_equal STREAM, response.media_type
    assert_includes response.body, ERB::Util.html_escape(RecoveryCodes::Generate.passkey_first)
    assert_empty shown
    assert_empty @user.recovery_codes
  end
end
