require "application_system_test_case"

# Your account's Passkeys and Recovery codes cards as a person meets them:
# adding a passkey through Chrome's virtual authenticator
# (`PasskeyHelper#with_virtual_authenticator`), renaming and removing one,
# making codes and seeing them once, and Confirm it's you before each change
# to how the person signs in, once the session's ten minutes are over.
#
# A sign-in counts as a confirmation, so a test that wants the dialog moves
# the session's `confirmed_at` back (`outside_the_window`), after the
# sign-in and before the press. A test signs in before it gives the account
# a passkey or codes: `sign_in_via_form` is the password alone, and an
# account with a second factor would be held at the second step.
class Admin::AccountPasskeysSystemTest < ApplicationSystemTestCase
  CONFIRM = "dialog#confirm-identity-dialog".freeze
  CODES = "dialog#new-recovery-codes-dialog".freeze
  CODES_TEXT = "#new-recovery-codes [data-admin--ui--recovery-codes-target=list]".freeze
  NAME = "dialog#passkey-add".freeze
  PASSKEY_READY = "#{CONFIRM} button[data-admin--passkeys--confirm-target=passkey]:not([disabled])".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @user = users(:one)
  end

  teardown { page.execute_script("delete navigator.clipboard; delete window.__copied; delete window.__blobs") }

  def account
    visit_screen admin_account_path
  end

  def outside_the_window
    Session.find_each { |session| session.update_column(:confirmed_at, (Session::CONFIRM_WINDOW + 1.minute).ago) }
  end

  def codes_shown
    assert_selector CODES, visible: true
    find(CODES_TEXT, visible: :all).text(:all).split
  end

  def make_codes
    texts = RecoveryCode.texts
    texts.each { |text| @user.recovery_codes.create!(digest: RecoveryCode.digest(text), generated_at: 1.day.ago) }
    texts
  end

  def confirm_with_password(password = "password")
    assert_selector "#{CONFIRM}[open]"
    within(CONFIRM) do
      fill_in "Password", with: password
      find("button[type=submit][form=confirm-identity-form]").click
    end
  end

  test "Add a passkey… adds it, shows ten codes, and the card lists it" do
    with_virtual_authenticator do
      sign_in_via_form(@user)
      account
      assert_selector "#account-passkeys", text: I18n.t("admin.components.account_screen.passkeys_card.none")

      press "Add a passkey…"
      assert_selector "#{NAME}[open]"
      assert_equal "passkey-add-name", page.evaluate_script("document.activeElement.id"), "the Name field is empty and has the focus"
      within(NAME) { fill_in "Name", with: "This browser" }
      press "Continue"

      assert_equal RecoveryCode::COUNT, codes_shown.size
      assert_selector "#passkey-#{@user.passkeys.sole.id}", text: "This browser"
      assert_selector "#account-passkeys [data-passkeys-foot]", text: "1 passkey"
      assert_selector "#account-recovery [data-recovery-status]", text: "10 of 10 codes left"
      assert_text "Passkey added."
      assert_no_selector "#{NAME}[open]"
      # Confirm it's you offers the passkey from now on.
      assert_selector "#{CONFIRM} button[data-admin--passkeys--confirm-target=passkey]", visible: :all
      assert_equal RecoveryCode::COUNT, @user.recovery_codes.unused.count
    end
  end

  test "Continue with no name says so and opens no prompt" do
    with_virtual_authenticator do
      sign_in_via_form(@user)
      account
      press "Add a passkey…"
      assert_selector "#{NAME}[open]"

      press "Continue"

      assert_selector "#{NAME} [role=alert]", text: I18n.t("admin.components.account_screen.passkey_dialog.name_blank")
      assert_empty @user.passkeys.reload
    end
  end

  test "after ten minutes Add asks Confirm it's you first, and the Name dialog follows by itself" do
    with_virtual_authenticator do
      sign_in_via_form(@user)
      account
      outside_the_window

      press "Add a passkey…"
      confirm_with_password

      assert_selector "#{NAME}[open]"
      assert_no_selector "#{CONFIRM}[open]"
      within(NAME) { fill_in "Name", with: "This browser" }
      press "Continue"
      assert_equal RecoveryCode::COUNT, codes_shown.size
      assert_equal [ "This browser" ], @user.passkeys.reload.map(&:name)
    end
  end

  test "when the ten minutes run out with the Name dialog open, Continue asks Confirm it's you and then adds the passkey" do
    with_virtual_authenticator do
      sign_in_via_form(@user)
      account
      press "Add a passkey…"
      assert_selector "#{NAME}[open]"
      outside_the_window

      within(NAME) { fill_in "Name", with: "This browser" }
      press "Continue"
      confirm_with_password

      assert_equal RecoveryCode::COUNT, codes_shown.size
      assert_equal [ "This browser" ], @user.passkeys.reload.map(&:name)
    end
  end

  test "Cancel in Confirm it's you adds nothing, and no Name dialog opens" do
    with_virtual_authenticator do
      sign_in_via_form(@user)
      account
      outside_the_window

      press "Add a passkey…"
      assert_selector "#{CONFIRM}[open]"
      within(CONFIRM) { press "Cancel" }

      assert_no_selector "#{CONFIRM}[open]"
      await_frames
      assert_no_selector "#{NAME}[open]"
    end
  end

  test "Rename saves the new name in the card and gives the focus back to Rename" do
    sign_in_via_form(@user)
    passkey = add_passkey(@user, client: fake_authenticator)
    account
    outside_the_window

    find("button[aria-label='Rename the passkey 1Password']").click
    within("dialog#passkey-#{passkey.id}-rename") do
      fill_in "Name", with: "Work laptop"
      press "Save name"
    end

    assert_selector "#passkey-#{passkey.id} [data-passkey-name]", text: "Work laptop"
    assert_no_selector "dialog[open]"
    assert_no_selector "#{CONFIRM}[open]" # renaming asks no confirmation
    assert_text "Passkey renamed."
    assert_equal "Rename the passkey Work laptop", page.evaluate_script("document.activeElement.getAttribute('aria-label')")
    assert_equal "Work laptop", passkey.reload.name
  end

  test "Remove… then Confirm with password removes it" do
    sign_in_via_form(@user)
    removed = add_passkey(@user, client: fake_authenticator)
    add_passkey(@user, client: fake_authenticator, name: "Phone")
    account
    outside_the_window

    find("button[aria-label='Remove the passkey 1Password']").click
    within("dialog#passkey-#{removed.id}-remove") { press "Remove passkey" }
    confirm_with_password

    assert_text "Passkey removed."
    assert_no_selector "#passkey-#{removed.id}"
    assert_selector "#account-passkeys [data-passkeys-foot]", text: "1 passkey"
    assert_not Passkey.exists?(removed.id)
  end

  test "Confirm it's you with the passkey carries the remove on" do
    with_virtual_authenticator do |authenticator|
      sign_in_via_form(@user)
      add_virtual_passkey(@user, authenticator)
      other = add_passkey(@user, client: fake_authenticator, name: "Phone")
      account
      outside_the_window

      find("button[aria-label='Remove the passkey Phone']").click
      within("dialog#passkey-#{other.id}-remove") { press "Remove passkey" }
      assert_selector PASSKEY_READY, text: "Use your passkey"
      find(PASSKEY_READY).click

      assert_text "Passkey removed."
      assert_not Passkey.exists?(other.id)
    end
  end

  test "Regenerate… shows ten new codes" do
    sign_in_via_form(@user)
    old = make_codes
    account

    press "Regenerate…"
    within("dialog#regenerate-recovery-codes") { press "Regenerate" }

    shown = codes_shown
    assert_equal RecoveryCode::COUNT, shown.size
    assert_empty old & shown
    assert_selector "#account-recovery [data-recovery-status]", text: "10 of 10 codes left"
  end

  test "a wrong password in Confirm it's you says so, and a right one carries the action on" do
    sign_in_via_form(@user)
    make_codes
    account
    outside_the_window

    press "Regenerate…"
    within("dialog#regenerate-recovery-codes") { press "Regenerate" }
    confirm_with_password("not-the-password")

    assert_selector "#{CONFIRM} [role=alert]", text: I18n.t("admin.components.ui.confirm_identity_dialog.wrong_password")
    assert_no_selector CODES
    assert_equal "", find("#{CONFIRM} input[name=password]").value, "the password is never drawn back"

    confirm_with_password

    assert_equal RecoveryCode::COUNT, codes_shown.size
    assert_no_selector "#{CONFIRM}[open]"
  end

  test "a cancelled confirmation is not re-sent later" do
    sign_in_via_form(@user)
    make_codes
    removed = add_passkey(@user, client: fake_authenticator)
    add_passkey(@user, client: fake_authenticator, name: "Phone")
    account
    outside_the_window

    find("button[aria-label='Remove the passkey 1Password']").click
    within("dialog#passkey-#{removed.id}-remove") { press "Remove passkey" }
    assert_selector "#{CONFIRM}[open]"
    within(CONFIRM) { press "Cancel" }
    assert_no_selector "#{CONFIRM}[open]"
    within("dialog#passkey-#{removed.id}-remove") { press "Cancel" }

    press "Regenerate…"
    within("dialog#regenerate-recovery-codes") { press "Regenerate" }
    confirm_with_password

    assert_equal RecoveryCode::COUNT, codes_shown.size
    assert Passkey.exists?(removed.id), "the cancelled remove stayed cancelled"
  end

  # Two marked forms refused by the gate before the person confirms: the
  # script remembers the last refused, so the later one is sent again and
  # the earlier is dropped without a word.
  test "two forms refused before a confirmation: only the later is sent again" do
    sign_in_via_form(@user)
    make_codes
    removed = add_passkey(@user, client: fake_authenticator)
    add_passkey(@user, client: fake_authenticator, name: "Phone")
    account
    outside_the_window
    page.execute_script(<<~JS)
      window.__refused = 0
      document.addEventListener("turbo:submit-end", (event) => { if (event.detail.fetchResponse?.statusCode === 403) window.__refused += 1 })
    JS

    find("button[aria-label='Remove the passkey 1Password']").click
    within("dialog#passkey-#{removed.id}-remove") { press "Remove passkey" }
    assert_selector "#{CONFIRM}[open]"
    await_js("window.__refused === 1")
    # by script: the regenerate form is the second request of a race the
    # test builds while the confirm dialog stands over the page.
    page.execute_script("document.querySelector('#regenerate-recovery-codes form[data-confirm-identity]').requestSubmit()")
    await_js("window.__refused === 2")
    confirm_with_password

    assert_equal RecoveryCode::COUNT, codes_shown.size
    assert Passkey.exists?(removed.id), "the earlier refused form is not sent again"
  end

  test "signing in with a code lands here with the warn notice" do
    add_passkey(@user, client: fake_authenticator)
    codes = make_codes
    visit admin_sign_in_path
    fill_in "Email", with: @user.email_address
    fill_in "Password", with: "password"
    press "Sign in"
    press "Use a recovery code"
    fill_in "Recovery code", with: codes.first
    press "Sign in"

    assert_current_path admin_account_path, wait: 15
    assert_selector "#account-passkeys [role=alert]", text: I18n.t("admin.accounts.passkeys.used_recovery", count: 9)
    assert_selector "#account-recovery [data-recovery-status]", text: "9 of 10 codes left"
  end

  test "after Done and a visit back, the page holds no code" do
    sign_in_via_form(@user)
    account

    press "Generate recovery codes…"
    shown = codes_shown
    within(CODES) do
      check "I have saved these codes"
      press "Done"
    end
    assert_no_selector CODES
    assert_no_selector CODES_TEXT, visible: :all
    shown.each { |code| assert_not_includes page.html, code }

    click_frame_link "Dashboard"
    assert_no_selector "#account-passkeys"
    page.go_back
    assert_selector "#account-recovery [data-recovery-status]", text: "10 of 10 codes left"

    html = page.html
    shown.each { |code| assert_not_includes html, code }
  end

  test "Escape closes the codes and forgets them" do
    sign_in_via_form(@user)
    account
    press "Generate recovery codes…"
    shown = codes_shown

    page.send_keys(:escape)

    assert_no_selector CODES
    assert_no_selector CODES_TEXT, visible: :all
    shown.each { |code| assert_not_includes page.html, code }
  end

  test "Done waits for the box, Download saves the codes, Copy copies them" do
    sign_in_via_form(@user)
    account
    page.execute_script(<<~JS)
      window.__copied = null
      Object.defineProperty(navigator, "clipboard", { configurable: true, value: { writeText: (text) => { window.__copied = text; return Promise.resolve() } } })
      window.__blobs = []
      const real = URL.createObjectURL.bind(URL)
      URL.createObjectURL = (blob) => { window.__blobs.push(blob); return real(blob) }
    JS

    press "Generate recovery codes…"
    shown = codes_shown
    within(CODES) do
      assert_selector "button[disabled]", text: "Done"

      press "Download"
      saved = page.evaluate_async_script("const done = arguments[0]; window.__blobs[0].text().then(done)")
      assert_equal "#{shown.join("\n")}\n", saved

      find("button[aria-label='Copy codes']").click
      assert_eventually { page.evaluate_script("window.__copied") == shown.join("\n") }

      check "I have saved these codes"
      assert_selector "button:not([disabled])", text: "Done"
      uncheck "I have saved these codes"
      assert_selector "button[disabled]", text: "Done"
    end
  end

  test "a box the browser restored as ticked lets Done go at once" do
    sign_in_via_form(@user)
    account
    press "Generate recovery codes…"
    codes_shown

    # The browser's restore of a ticked box, then the controller connecting
    # again over it: no change event is fired.
    page.execute_script(<<~JS)
      const element = document.getElementById("new-recovery-codes")
      element.querySelector("input[name=saved]").checked = true
      element.removeAttribute("data-controller")
    JS
    await_frames
    page.execute_script("document.getElementById('new-recovery-codes').setAttribute('data-controller', 'admin--ui--recovery-codes')")

    assert_selector "#{CODES} button:not([disabled])", text: "Done"
  end

  test "the codes dialog: Tab reaches Copy codes, Download and the box, Space ticks it, and Enter on Done closes it" do
    sign_in_via_form(@user)
    account
    press "Generate recovery codes…"
    codes_shown

    stop_on "#{CODES} button[data-admin--ui--clipboard-target=button], #{CODES} [data-action*='admin--ui--clipboard#copy']"
    stop_on "#{CODES} button[data-action*='recovery-codes#download']"
    stop_on "#{CODES} input[name=saved]"
    page.send_keys(:space)
    assert page.evaluate_script("document.activeElement.checked"), "Space ticks the box"
    stop_on "#{CODES} button[data-admin--ui--recovery-codes-target=done]"
    page.send_keys(:enter)

    assert_no_selector CODES
    assert_no_selector CODES_TEXT, visible: :all
  end

  test "Confirm it's you starts on the password, Enter sends it, and Escape backs out" do
    sign_in_via_form(@user)
    make_codes
    account
    outside_the_window

    press "Regenerate…"
    within("dialog#regenerate-recovery-codes") { press "Regenerate" }
    assert_selector "#{CONFIRM}[open]"
    assert_equal "confirm-identity-password", page.evaluate_script("document.activeElement.id")
    page.send_keys(:escape)
    assert_no_selector "#{CONFIRM}[open]"
    await_frames
    assert_no_selector CODES

    within("dialog#regenerate-recovery-codes") { press "Regenerate" }
    assert_selector "#{CONFIRM}[open]"
    assert_equal "confirm-identity-password", page.evaluate_script("document.activeElement.id")
    page.send_keys("password", :enter)

    assert_equal RecoveryCode::COUNT, codes_shown.size
  end
end
