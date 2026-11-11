# Passkeys and recovery codes: the screens and their words

Design System v208 (index 1794419055-a812), with the confirm dialog's words from v209 (index 1794419343-52dc), cards **StudioPasskeySignIn** (sign-in button, second step, enrolment, wizard step) and **StudioPasskeys** (Your account's Passkeys and Recovery codes cards and dialogs, codes shown once, Settings → Sign-in, the two mails). Both are marked Decided, not built. The spec is `2026-11-10-studio-sign-in-design.md` §3, §5, §6 and §8.

## Owner decisions (2026-11-11)

1. **Confirm it's you before a security change.** Adding or removing a passkey, and generating or regenerating recovery codes, ask for the password or a passkey first, unless the person confirmed in the last 10 minutes. The dialog's words are below, from v209.
2. **Default policy.** In production it is Owners and admins until an owner changes it. In development it is Nobody.
3. **When a policy takes effect.** At each covered person's next sign-in. A session already open carries on.

Earlier decisions:
- Passkeys are WebAuthn through `webauthn-ruby`.
- Several passkeys per person, each with a name the person chooses.
- Discoverable credentials, registered to the registrable domain of `PUBLIC_HOST`.
- Ten single-use recovery codes, stored only as digests.
- All of this lands in one PR.

## New parts

- **`Admin::Ui::RecoveryCodesComponent`**, the codes block. Your account, enrolment and the wizard all draw it, so it is shared from the start.
- **Two icons:** `:fingerprint`, for Passkeys, the policy card and the passkey button; and `:life_buoy`, for Recovery codes.
- **Everything else** is existing components: SettingsCard, ActionZone, ConfirmDialog, Dialog, CopyValue, Notice, Button, Badge and TimeAgo.

## Placement and behaviour

### Sign-in panel
- **"Sign in with a passkey"** sits under the password form's Sign in, after an "or" divider. It is a secondary, full-width button with the fingerprint icon, so Sign in stays the panel's only primary.
- **The bot check** stays inside the password form. A passkey sign-in never asks for it.
- **The email field** gets `autocomplete="username webauthn"`.
- **No passkey support:** the divider and the button stay hidden. They stand below the form, so nothing above moves.
- **A cancelled prompt** says nothing.

### The second step
- **When:** after a right password, for an account that holds a passkey or recovery codes.
- **How long it is held:** 5 minutes. The cookie stores only the user's id and the time, never the password.
- **Failures** count in the account's throttle bucket. A wrong code and a used code get the same sentence.
- **An account with codes but no passkey** opens straight on the code view.

### Enrolment
- A person the policy covers who has no passkey is taken to enrolment at their next sign-in.
- Every CS Studio page then redirects to it until they add a passkey. Sign out stays open.
- The recovery codes follow as the next step.

### Your account → Passkeys card
- **Rows:** the name, "Added …", "Last used …" or "Never used", then Rename and Remove….
- **Remove** is a destructive confirm. On the last passkey while the policy covers the person, Remove is disabled, with a line in the row saying why.
- **Add** opens a narrow dialog with a Name field (prefilled from the authenticator's name when the browser gives one), then the browser's own prompt.
- **The first passkey** also generates and shows the recovery codes.

### Recovery codes card
- **Status line:** "N of 10 left · made <date>", with Regenerate…, or Generate… when there are none.
- **Regenerate** asks first, in a confirm that is not destructive.
- **Two or fewer codes left:** a warn notice.

### The codes, shown once
- Ten codes as `XXXX-XXXX`, in two mono columns.
- "Copy codes" (CopyValue) and "Download" (a .txt file).
- "Done" stays disabled until "I have saved these codes" is ticked. × still closes the dialog.

### After signing in with a code
The person lands on Your account at `#passkeys` with a warn notice (`used_recovery`).

### Settings → Sign-in
- An owner-only section after Mail, saved with the floating save bar.
- The choice is segmented radios, with the definition of "admins" as a help line.
- A line counts the covered people who have no passkey yet.

### Mails
`SignInMailer#passkey_added` and `#recovery_code_used`, in the existing layout, each with "Open Your account".

## Exact words (keys)

### Sign-in panel

- `admin.sessions.new.or`: "or"
- `admin.sessions.new.passkey`: "Sign in with a passkey"
- `admin.sessions.passkey_failed`: "That passkey didn't work. Try again, or sign in with your password."
- `admin.sessions.second_factor_expired`: "That took too long. Sign in again."

### Second step

Keys under `admin.second_factor`:
- `show.title`: "Confirm it's you"
- `show.lead`: "Use your passkey to finish signing in as %{email}."
- `show.use_passkey`: "Use your passkey"
- `show.use_code`: "Use a recovery code"
- `show.code`: "Recovery code"
- `show.code_help`: "One of the ten codes you saved. Each works once."
- `show.submit_code`: "Sign in"
- `show.start_over`: "Start over"
- `passkey_failed`: "That passkey didn't work. Try again, or use a recovery code."
- `passkey_failed_no_codes`: "That passkey didn't work. Try again."
- `code_failed`: "That code didn't work. Check it, or use another one."

### Enrolment

Keys under `admin.enrolment.show`:
- `title`: "Add a passkey"
- `lead.owners_and_admins`: "This site asks owners and admins to sign in with a passkey. Add one to go on."
- `lead.everyone`: "This site asks everyone to sign in with a passkey. Add one to go on."
- `name`: "Name"
- `name_help`: "A name to tell your passkeys apart, like "1Password" or "MacBook"."
- `add`: "Add passkey"
- `sign_out`: "Sign out"
- `failed`: "The passkey wasn't added. Try again."

### Setup wizard

Keys under `setup`:
- `passkey.title`: "Add a passkey"
- `passkey.lead`: "Sign in with your device's unlock instead of your password. A passkey can't be phished or guessed."
- `passkey.add`: "Add passkey"
- `passkey.skip`: "Skip for now"
- `steps.passkey`: "Passkey"

The step is skippable unless the policy requires a passkey.

### Your account → Passkeys card

Keys under `admin.components.account_screen.passkeys_card`:
- `title`: "Passkeys"
- `intro`: "Sign in with your device's unlock instead of your password. Add one for each device or password manager you use."
- `added`: "Added %{date}"
- `last_used_html`: "Last used %{time}"
- `never_used`: "Never used"
- `rename`: "Rename"
- `rename_label`: "Rename the passkey %{name}"
- `remove`: "Remove…"
- `remove_label`: "Remove the passkey %{name}"
- `last_required`: "This site asks you to sign in with a passkey. Add another before removing this one."
- `count`:
  - one: "1 passkey"
  - other: "%{count} passkeys"
- `none`: "You have no passkeys. You sign in with your password."
- `add`: "Add a passkey…"

### Passkey dialogs

Keys under `admin.components.account_screen.passkey_dialog`:
- `add_title`: "Add a passkey"
- `name`: "Name"
- `name_help`: "A name to tell your passkeys apart, like "1Password" or "MacBook"."
- `name_blank`: "Give the passkey a name."
- `continue`: "Continue"
- `failed`: "The passkey wasn't added. Try again."
- `rename_title`: "Rename passkey"
- `save_name`: "Save name"
- `remove_title`: "Remove the passkey "%{name}"?"
- `remove_body`: "You can't sign in with it any more. Delete it from the device or password manager too."
- `remove_last`: "It's your last passkey: you'll sign in with your password again."
- `remove_confirm`: "Remove passkey"

### Recovery codes card

Keys under `admin.components.account_screen.recovery_card`:
- `title`: "Recovery codes"
- `intro`: "Sign in with one when your passkeys aren't at hand. Each code works once."
- `left`: "%{left} of 10 codes left · made %{date}"
- `none`: "You have no recovery codes."
- `low`:
  - one: "1 code left. Regenerate them before you run out."
  - other: "%{count} codes left. Regenerate them before you run out."
- `out`: "No codes left. Regenerate them now."
- `generate`: "Generate recovery codes…"
- `regenerate`: "Regenerate…"
- `regenerate_title`: "Regenerate recovery codes?"
- `regenerate_body`:
  - one: "Your 1 unused code stops working, and you get ten new ones to save."
  - other: "Your %{count} unused codes stop working, and you get ten new ones to save."
- `regenerate_confirm`: "Regenerate"

### The codes, shown once

Keys under `admin.components.ui.recovery_codes`:
- `title`: "Save your recovery codes"
- `body`: "Each code signs you in once when your passkeys aren't at hand. This is the only time they're shown: keep them somewhere safe, apart from your devices."
- `list_label`: "Recovery codes"
- `copy`: "Copy codes"
- `download`: "Download"
- `saved`: "I have saved these codes"
- `done`: "Done"

### Your account's toasts and notices

Keys under `admin.accounts.passkeys`:
- `added`: "Passkey added."
- `renamed`: "Passkey renamed."
- `removed`: "Passkey removed."
- `used_recovery`:
  - one: "You signed in with a recovery code. 1 code is left. If you lost a passkey, remove it and add a new one."
  - other: "You signed in with a recovery code. %{count} codes are left. If you lost a passkey, remove it and add a new one."
- `used_last_recovery`: "You signed in with your last recovery code. Generate new ones, and if you lost a passkey, remove it and add a new one."

### Settings → Sign-in

Keys under `admin.components.settings_screen.sign_in_card`:
- `title`: "Sign-in"
- `intro`: "Who must sign in with a passkey. For them a password alone is no longer enough."
- `legend`: "Passkey required for"
- `policies`: "Nobody" / "Owners and admins" / "Everyone"
- `admins_help`: "Admins are people who may manage users, groups or API tokens."
- `uncovered`:
  - one: "1 person this covers has no passkey yet. They're asked to add one at their next sign-in; until then, nothing changes for them."
  - other: "%{count} people this covers have no passkey yet. Each is asked to add one at their next sign-in; until then, nothing changes for them."
- `all_covered`: "Everyone this covers has a passkey."
- `saved`: "Sign-in policy saved."

### Mail: a passkey was added

Keys under `mail.passkey_added`:
- subject: "A passkey was added to your account on %{site}"
- intro: "A passkey named “%{name}” was added to your account on %{site} at %{time}."
- button: "Open Your account"
- outro: "If this wasn't you, remove the passkey there and change your password."

### Mail: a recovery code was used

Keys under `mail.recovery_code_used`:
- subject: "A recovery code was used on %{site}"
- intro:
  - one: "A recovery code was used to sign in to your account on %{site} at %{time}, from the address %{address}. 1 code is left."
  - other: "A recovery code was used to sign in to your account on %{site} at %{time}, from the address %{address}. %{count} codes are left."
- button: "Open Your account"
- outro: "If this wasn't you, regenerate your recovery codes and change your password."

### Confirm it's you (Design System v209, index 1794419343-52dc)

- **Appears before** adding a passkey, removing a passkey, generating recovery codes and regenerating them. Not before renaming a passkey or ending a session.
- **The window:** the session row keeps `confirmed_at`. Within 10 minutes of it the four actions go straight on. A sign-in counts as a confirmation. After 10 minutes it asks again. No clock is shown.
- **The dialog:** `DialogComponent` `form_narrow`.
  - With a passkey: "Use your passkey" (primary), an "or" divider, the Password field (`PasswordFieldComponent`), and "Confirm with password" (secondary) beside Cancel.
  - Without a passkey: the Password field, and "Confirm" (primary) beside Cancel.
  - No recovery code here: codes sign in, they don't confirm a change.
- **Failures:** wrong passwords count in the account's throttle bucket. A cancelled passkey prompt says nothing.
- **Once confirmed,** the action that opened the dialog carries on by itself (the browser's passkey prompt, the remove, or the codes).
- **Audit:** a failed confirmation records `session.confirmation_failed`. A successful one records nothing.

Keys under `admin.components.account_screen.confirm_dialog`:
- `title`: "Confirm it's you"
- `lead_passkey`: "To change how you sign in, confirm with your passkey or your password."
- `lead_password`: "To change how you sign in, confirm with your password."
- `use_passkey`: "Use your passkey"
- `or`: "or"
- `password`: "Password"
- `confirm_password`: "Confirm with password"
- `confirm`: "Confirm"
- `passkey_failed`: "That passkey didn't work. Try again, or use your password."
- `wrong_password`: "That password isn't right."
- `limited`: "Try again in a few minutes."

### Also recorded on the cards (v209)

The wizard's "Skip for now" is drawn only when the policy doesn't cover the founding owner: with production's default, Owners and admins, it is not drawn; with development's Nobody, it is.
