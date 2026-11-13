# Single sign-on screens: Design System card StudioSingleSignOn

Design System https://claude.ai/artifact/Pg9o6tAeyWk98YFsrMmXxT, version index 1794552254-57d8 (v218). A plain copy of the card's screens, decisions D1 to D6 and keys, so it travels with the branch; tasks 11 to 14 build to it.


Screens:
1. SSO configured: password form unchanged, "or" divider, two secondary full-width buttons: "Sign in with Okta" first, then passkey. Sign in stays the only primary.
2. SSO_REQUIRED: lead "This site signs you in with Okta.", provider button primary, small "Owner sign-in" link. Owner path (?owner=1): password form + passkey, lead "owners only", "Sign in with Okta instead". A non-owner on the owner path gets the ordinary refusal (never reveals who is an owner).
3. Refusals: provider errors redirect to sign-in panel's danger notice. One sentence for all account reasons (no invited account, unverified email, linked account gone), audited sso.refused; another for unfinished way in (cancel, provider error, bad state).
4. Invitation: password form, "or", "Continue with Okta". Under SSO_REQUIRED a non-owner's invitation shows only "Continue with Okta" as primary. Email mismatch: page names both addresses.
5. User editor: badge "Signs in with Okta"; owners-only "Single sign-on" zone after the Owner zone with "Unlink…"; not drawn for owners. Unlink confirm dialog (not destructive), signs person out everywhere, mails a password-setting link, toast.
6. Your account (linked): Password card replaced by "Sign-in" card; Passkeys and Recovery codes not drawn; Sessions stays.
7. System status: Single sign-on row, OK (issuer answers; + "Required for everyone but owners."), Warning (didn't answer), Off.

Design decisions (for the owner to check):
- D1 env gives the provider NAME (e.g. SSO_NAME="Okta"), not a button label.
- D2 placement as above.
- D3 an SSO-specific refusal sentence.
- D4 unlink ends the person's sessions.
- D5 linking deletes the account's passkeys and recovery codes (spec silent).
- D6 no provider logos.

Keys:
admin.sessions.new: sso "Sign in with %{provider}"; sso_lead "This site signs you in with %{provider}."; owner_sign_in / owner_title "Owner sign-in"; owner_lead "For owners only. Everyone else signs in with %{provider}."; sso_instead "Sign in with %{provider} instead"
admin.sessions: sso_refused "Your %{provider} account can't sign in to this site. Ask an owner to invite you."; sso_unfinished "Signing in with %{provider} didn't finish. Try again."
invitations.show: or "or"; sso "Continue with %{provider}"; sso_mismatch "%{provider} signed you in as %{got}, but this invitation is for %{email}. Sign in to %{provider} with that address, or ask for a new invitation."
admin.components.users_screen.sso_zone: badge "Signs in with %{provider}"; heading "Single sign-on"; body "%{name} signs in with %{provider} and has no password here."; trigger "Unlink…"; title "Unlink %{name} from %{provider}?"; confirm_body "%{name} can no longer sign in with %{provider}, and is signed out everywhere. They get a mail to set a password here."; confirm "Unlink"; unlinked "%{name} is unlinked from %{provider}. A mail to set a password is on its way."
admin.components.account_screen.sso_card: title "Sign-in"; intro "You sign in with %{provider}."; body "Your password, your second factor and signing out of %{provider} are managed there. Ask an owner if you need to sign in another way."
System status: sso.label "Single sign-on"; sso.ok "%{provider} (%{issuer}) answers."; sso.required "Required for everyone but owners."; sso.unreachable "%{provider} (%{issuer}) didn't answer: %{reason}. Nobody can sign in with it until it does."; sso.off "Not set up. The hosting reference lists its variables."
Audit: adds sso.unlinked, and session.ended reason sso_unlinked.
