require "test_helper"

# "Your account", the screen, whose third card is "Change my password": any
# user may change their own password, and the screen is reachable by every
# user from the account menu.
class Admin::AccountsTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
  end

  test "every signed-in user reaches it from the account menu" do
    sign_in_as(users(:reader))

    get "/cs-studio/api_tokens"
    assert_select ".admin-account a[href='/cs-studio/account']", text: "Your account"
    assert_select ".admin-account a#account-identity[href='/cs-studio/account']"

    get "/cs-studio/account"
    assert_response :success
    assert_select "input[type=password][name=current_password]"
  end

  test "signed out, it redirects to sign-in" do
    get "/cs-studio/account"
    assert_redirected_to "/cs-studio/sign-in"
  end

  test "a wrong current password fails and changes nothing" do
    sign_in_as(users(:reader))

    patch "/cs-studio/account/password", params: { current_password: "wrong", password: "new-password-1", password_confirmation: "new-password-1" }

    assert_response :unprocessable_entity
    # In the Password card, where the form is, not above the cards.
    assert_select "#password .admin-error-summary[role=alert] li", text: "That's not your current password."
    assert_select ".admin-error-summary", count: 1
    assert_select "#current_password-errors", text: /That's not your current password\./
    assert_select "#current_password[aria-invalid=true][aria-describedby~='current_password-errors']"
    assert users(:reader).reload.authenticate("password")
  end

  test "a refused password change never renders what was typed" do
    sign_in_as(users(:reader))

    patch "/cs-studio/account/password", params: { current_password: "wrong-secret-9", password: "typed-new-password-9", password_confirmation: "typed-new-password-9" }

    assert_response :unprocessable_entity
    assert_not_includes response.body, "wrong-secret-9"
    assert_not_includes response.body, "typed-new-password-9"
  end

  # The controller loads the card's rows for every answer that draws the
  # screen (`AccountsController#load_sessions`), and the view queries
  # nothing itself: the screen, a refused password and a refused name all
  # show the person's live sessions and none that expired. "Sign out
  # everywhere else" waits for the forms (`admin--saving--pending-lock`).
  test "the Sessions card shows the live sessions on the screen and on both refusals" do
    user = users(:reader)
    sign_in_as(user)
    other = Session.start(user: user, method: "password", user_agent: nil, ip_address: nil, at: 1.hour.ago)
    expired = Session.start(user: user, method: "password", user_agent: nil, ip_address: nil, at: 15.days.ago)

    [
      -> { get "/cs-studio/account" },
      -> { patch "/cs-studio/account/password", params: { current_password: "wrong", password: "new-password-1", password_confirmation: "new-password-1" } },
      -> { patch "/cs-studio/account/profile", params: { name: "a" * 121 } }
    ].each do |request|
      request.call
      assert_select "#account-sessions li[id^='session-']", count: 2
      assert_select "#session-#{other.id}"
      assert_select "#session-#{expired.id}", count: 0
      assert_select "#account-sessions-foot[data-controller~='admin--saving--pending-lock']" do
        assert_select "button[data-admin--saving--pending-lock-target=control]", text: "Sign out everywhere else…"
        assert_select "p[data-admin--saving--pending-lock-target=hint][hidden]"
      end
    end
  end

  test "the screen promises what the code does, and links the reset flow from the card's footer" do
    put_mail_state(:working)
    sign_in_as(users(:reader))

    get "/cs-studio/account"

    # The page is "Your account"; its cards are
    # Profile, Notes, Password, Passkeys, Recovery codes and Sessions, in that
    # order; and the promise about sessions stands directly under the
    # Password card's title.
    assert_select "title", text: "Your account"
    assert_select "h1", text: "Your account", count: 1
    assert_equal [ "Profile", "Notes", "Password", "Passkeys", "Recovery codes", "Sessions" ],
      css_select("turbo-frame#content section .admin-settings-card__head h2").map { |heading| heading.text.strip }
    # Passkeys, Recovery codes and Sessions stand in neither form: nothing in
    # them is a change either save bar counts.
    assert_select "form section#account-passkeys, form section#account-recovery, form section#account-sessions", count: 0
    assert_select "form#password-form + div > section#account-passkeys + section#account-recovery"
    assert_select "form#profile-form section", count: 2
    assert_select "form#password-form section[aria-labelledby=account-password]" do
      assert_select ".admin-settings-card__head:has(h2#account-password) > p", text: "You'll stay signed in here. Other sessions are signed out."
      assert_select "input[type=password]", count: 3
    end
    # The Password card's footer is the card's own and sits inside it, under
    # a line; the first form's stays under its two cards.
    assert_select "form#password-form section[aria-labelledby=account-password] > .admin-save-bar.admin-save-bar--contained.border-t:last-child button[type=submit]", text: "Change password"
    assert_select "form#password-form section ~ .admin-save-bar", count: 0
    assert_select "form#profile-form > section ~ .admin-save-bar.sticky:not(.admin-save-bar--contained) button[type=submit]", text: "Save changes"
    assert_select "form#profile-form section .admin-save-bar", count: 0
    assert_select "h1 + p", count: 0
    assert_select "#password-form .admin-save-bar a[href='/cs-studio/password/new']", text: "Forgot your current password?"
    assert_select "#profile-form .admin-save-bar a", text: "Forgot your current password?", count: 0
    assert_select ".admin-save-bar", count: 2
  end

  test "Your account shows the reset link only when mail is ready, and nothing in its place" do
    sign_in_as(users(:reader))
    with_mail_state(:untested) do
      get "/cs-studio/account"
      assert_select "#password-form .admin-save-bar a", text: /Forgot/, count: 0
      assert_select "#password-form", text: /Ask the site's owner/, count: 0
    end
    with_mail_state(:working) do
      get "/cs-studio/account"
      assert_select "#password-form .admin-save-bar a[href='/cs-studio/password/new']", text: "Forgot your current password?"
    end
  end

  test "visiting the reset flow signed in signs nobody out" do
    put_mail_state(:working)
    user = users(:reader)
    sign_in_as(user)
    session_id = Current.session.id

    get "/cs-studio/password/new"

    assert_response :success
    assert Session.exists?(session_id)
    get "/cs-studio/account"
    assert_response :success
  end

  test "a mismatched confirmation fails" do
    sign_in_as(users(:reader))

    patch "/cs-studio/account/password", params: { current_password: "password", password: "new-password-1", password_confirmation: "other" }

    assert_response :unprocessable_entity
    assert users(:reader).reload.authenticate("password")
  end

  test "a new password under 12 characters is refused with the rule's own message" do
    sign_in_as(users(:reader))

    patch "/cs-studio/account/password", params: { current_password: "password", password: "elevenchars", password_confirmation: "elevenchars" }

    assert_response :unprocessable_entity
    assert_select ".admin-error-summary[role=alert] li", text: "Use at least 12 characters."
    assert users(:reader).reload.authenticate("password")
  end

  test "Your account refuses a leaked password in its card" do
    sign_in_as(users(:reader))

    with_leaked_password_check(leaked: [ "correct horse battery" ]) do
      patch "/cs-studio/account/password", params: { current_password: "password", password: "correct horse battery", password_confirmation: "correct horse battery" }
    end

    assert_response :unprocessable_entity
    assert_select "#password .admin-error-summary[role=alert] li", text: "This password is in a list of leaked passwords, so it isn't safe to use. Choose another one."
    # And under the new password's own field, tied to its input.
    assert_select "#new_password-errors", text: /#{Regexp.escape("This password is in a list of leaked passwords, so it isn't safe to use. Choose another one.")}/
    assert_select "#new_password[aria-invalid=true][aria-describedby~='new_password-errors']"
    assert_not_includes response.body, "correct horse battery"
    assert users(:reader).reload.authenticate("password")
  end

  # Have I Been Pwned out of reach: the password is accepted (the check
  # fails open), and the person is told only that it changed.
  test "with the range lookup unavailable a new password is saved and the save says nothing of the check" do
    sign_in_as(users(:reader))

    with_leaked_password_check(leaked: [ "correct horse battery" ], unavailable: Errno::ECONNREFUSED) do
      patch "/cs-studio/account/password", params: { current_password: "password", password: "correct horse battery", password_confirmation: "correct horse battery" }
    end

    assert_equal 1, leaked_password_requests.size
    assert_redirected_to "/cs-studio/account#password"
    follow_redirect!
    assert_select "#password [data-password-saved][role=status]", text: "Password changed. Your other sessions were signed out."
    assert_no_match(/leaked|could not be made|check/i, css_select("#password").text)
    assert users(:reader).reload.authenticate("correct horse battery")
  end

  test "a success changes the password and signs out other sessions only" do
    user = users(:reader)
    other_session = Session.start(user: user, method: "password", user_agent: nil, ip_address: nil)
    sign_in_as(user)
    current_session = Current.session

    patch "/cs-studio/account/password", params: { current_password: "password", password: "new-password-1", password_confirmation: "new-password-1" }

    assert_redirected_to "/cs-studio/account#password"
    follow_redirect!
    # Said in the card, where the form is, and by no toast.
    assert_select "#password [data-password-saved][role=status][tabindex='-1']", text: "Password changed. Your other sessions were signed out."
    assert_select "#toasts .admin-toast", count: 0
    assert user.reload.authenticate("new-password-1")
    assert_not Session.exists?(other_session.id)
    assert Session.exists?(current_session.id)
    # Still signed in here: the next request is served, not sent to sign-in.
    get "/cs-studio/account"
    assert_response :success

    event = Audit::Event.find_by!(action: "user.updated", subject: user)
    assert_not_includes event.attributes.to_json, "new-password-1"
    assert_not_includes event.attributes.to_json, user.password_digest
  end

  test "a user saves their own name" do
    user = users(:reader)
    sign_in_as(user)

    patch "/cs-studio/account/profile", params: { name: "Ada" }

    assert_redirected_to "/cs-studio/account"
    assert_equal "Ada", user.reload.name
  end

  test "Your account saved as rendered writes nothing and audits nothing" do
    user = users(:reader)
    sign_in_as(user)
    stored_at = user.reload.updated_at

    assert_no_difference -> { Audit::Event.where(action: "user.updated").count } do
      patch "/cs-studio/account/profile", params: {
        name: "", notes_sound: user.notes_sound ? "1" : "0", notes_desktop: user.notes_desktop ? "1" : "0"
      }
    end

    assert_redirected_to "/cs-studio/account"
    assert_equal stored_at, user.reload.updated_at
  end

  # The account screen has a second form: Turbo gets a stream that keeps the
  # screen (and what the password form holds) instead of a redirect.
  test "saving a name answers Turbo with a stream: the sidebar's account block and a toast" do
    sign_in_as(users(:one))
    patch admin_account_profile_path, params: { name: "Ada <i>L</i>" }, as: :turbo_stream

    assert_response :ok
    assert_equal "Ada <i>L</i>", users(:one).reload.name
    assert_select "turbo-stream[action=replace][target=account-identity]"
    assert_select "turbo-stream[action=append][target=toasts]"
    assert_includes response.body, "Settings saved"
    assert_not_includes response.body, "Settings saved."
    assert_includes response.body, "Ada &lt;i&gt;L&lt;/i&gt;"
    assert_not_includes response.body, "<i>L</i>"
  end

  # <body> is not drawn again by that answer, so the two notes settings the
  # scripts act on travel in it: the element the layout holds, as stored now.
  test "the save's stream hands the stored notes settings to the tab, and the layout holds the same element" do
    sign_in_as(users(:one))
    get "/cs-studio/account"
    assert_select "body > span#notes-alert-settings[hidden][data-admin--notes--alert-target=settings][data-sound=true][data-desktop=false]", count: 1

    patch admin_account_profile_path, params: { name: "Ada", notes_sound: "0", notes_desktop: "1" }, as: :turbo_stream

    assert_select "turbo-stream[action=replace][target=notes-alert-settings] template span#notes-alert-settings[data-admin--notes--alert-target=settings][data-sound=false][data-desktop=true]"
  end

  # The format is decided without `respond_to`: the name is saved by then.
  test "a client that takes neither a stream nor HTML is redirected, never told 406 about a save that happened" do
    sign_in_as(users(:one))
    patch admin_account_profile_path, params: { name: "Json Client" }, headers: { "Accept" => "application/json" }

    assert_redirected_to "/cs-studio/account"
    assert_equal "Json Client", users(:one).reload.name
  end

  test "signed out, saving a name redirects to sign-in" do
    patch "/cs-studio/account/profile", params: { name: "Ada" }
    assert_redirected_to "/cs-studio/sign-in"
  end

  # --- the Notes switches --------------------------------------------------------

  test "the name and the two Notes switches are one form with one footer, and saving keeps the screen" do
    sign_in_as(users(:reader))
    get "/cs-studio/account"

    assert_select "form#profile-form[action='/cs-studio/account/profile'][data-controller='admin--saving--save-bar']" do
      # "Your account", then two cards of one width, Profile and Notes, and
      # one footer under both, whose button is "Save changes".
      assert_select "section.admin-settings-card", count: 2
      assert_select "section[aria-labelledby=account-profile] h2#account-profile", text: "Profile"
      assert_select "section[aria-labelledby=account-profile] label[for=name]", text: "Your name"
      assert_select "section[aria-labelledby=account-profile] input[name=name]"
      assert_select "section[aria-labelledby=account-notes] h2#account-notes", text: "Notes"
      assert_select "section ~ [data-admin--saving--save-bar-target=bar] button[type=submit]", text: "Save changes"
      assert_select "input[type=checkbox][name=notes_sound][role=switch][checked]"
      assert_select "input[type=checkbox][name=notes_desktop][role=switch]:not([checked])"
      assert_select "label", text: "Play a sound when I'm mentioned"
      assert_select "label", text: "Show a desktop notification when I'm mentioned"
      # The permission is this browser's: both lines are drawn hidden, and
      # the script shows one while the switch is on.
      assert_select "[data-controller='admin--notes--permission'] input[name=notes_desktop][data-admin--notes--permission-target=switch]"
      assert_select "[data-controller='admin--notes--permission'] [hidden] button[type=button]:not([name])", text: "Allow in this browser"
      assert_select "[data-controller='admin--notes--permission'] [hidden]", text: "Blocked in this browser. Change it in the site settings of your browser."
      assert_select "[data-admin--saving--save-bar-target=bar]", count: 1
    end
    assert_select "form#notes-form", count: 0
    assert_select "body[data-admin--notes--alert-sound-value=true][data-admin--notes--alert-desktop-value=false][data-admin--notes--alert-person-value='#{users(:reader).id}']"
    # Changing the password draws the screen again: it waits for that one form.
    assert_select "form#password-form[data-admin--saving--save-bar-after-value='profile-form']"

    patch "/cs-studio/account/profile", params: { name: "Ada", notes_sound: "0", notes_desktop: "1" }, headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" }

    assert_response :ok
    assert_select "turbo-stream[action=append][target=toasts]"
    assert_select "turbo-stream[action=replace][target=account-identity]"
    assert_equal [ "Ada", false, true ], users(:reader).reload.then { |user| [ user.name, user.notes_sound, user.notes_desktop ] }
    # One press, one write, one event.
    assert_equal 1, Audit::Event.where(action: "user.updated", subject: users(:reader)).count

    get "/cs-studio/account"
    assert_select "input[name=notes_sound]:not([checked])"
    assert_select "input[name=notes_desktop][checked]"
    assert_select "body[data-admin--notes--alert-sound-value=false][data-admin--notes--alert-desktop-value=true]"
  end

  test "a request that sends no switch leaves both as they are" do
    users(:reader).update!(notes_sound: false, notes_desktop: true)
    sign_in_as(users(:reader))

    patch "/cs-studio/account/profile", params: { name: "Ada" }

    assert_redirected_to "/cs-studio/account"
    assert_equal [ "Ada", false, true ], users(:reader).reload.then { |user| [ user.name, user.notes_sound, user.notes_desktop ] }
  end

  test "a refused name writes neither the name nor a switch, and the form comes back with what was sent" do
    sign_in_as(users(:reader))

    patch "/cs-studio/account/profile", params: { name: "a" * 121, notes_sound: "0", notes_desktop: "1" }

    assert_response :unprocessable_entity
    assert_equal [ nil, true, false ], users(:reader).reload.then { |user| [ user.name, user.notes_sound, user.notes_desktop ] }
    assert_select "form#profile-form[data-admin--saving--save-bar-dirty-value=true]" do
      assert_select "input[name=name][value='#{"a" * 121}']"
      assert_select "input[name=notes_sound]:not([checked])"
      assert_select "input[name=notes_desktop][checked]"
    end
    # The rest of the page is drawn from what is stored, not from what was refused.
    assert_select "body[data-admin--notes--alert-sound-value=true][data-admin--notes--alert-desktop-value=false]"
  end

  # Only ever the signed-in person's own: the request names no user.
  test "the switches are saved for whoever is signed in, whatever else the request names" do
    sign_in_as(users(:two))

    patch "/cs-studio/account/profile", params: { name: "Dana", notes_sound: "0", notes_desktop: "1", id: users(:reader).id, user_id: users(:reader).id }

    assert_equal [ false, true ], users(:two).reload.then { |user| [ user.notes_sound, user.notes_desktop ] }
    assert_equal [ true, false ], users(:reader).reload.then { |user| [ user.notes_sound, user.notes_desktop ] }
  end

  test "signed out, saving the switches redirects to sign-in and writes nothing" do
    patch "/cs-studio/account/profile", params: { name: "Ada", notes_sound: "0", notes_desktop: "1" }

    assert_redirected_to "/cs-studio/sign-in"
    assert User.where(notes_sound: false).or(User.where(notes_desktop: true)).none?
  end

  # The page is "Your account", and its address
  # says so. The old one, which named the password alone, leads there.
  test "the account page is at /account; the old address moves there for good, with the language it was asked in" do
    sign_in_as(users(:reader))

    get "/cs-studio/account"
    assert_response :success
    assert_select "h1", text: "Your account"

    get "/cs-studio/account/password"
    assert_response :moved_permanently
    assert_redirected_to "/cs-studio/account"

    get "/cs-studio/account/password", params: { locale: "de" }
    assert_response :moved_permanently
    assert_redirected_to "/cs-studio/account?locale=de"
  end

  test "the old address still asks for a sign-in first, and names no account page to someone signed out" do
    get "/cs-studio/account/password"

    assert_redirected_to "/cs-studio/sign-in"
  end

  test "the Password card is #password, and the password form still posts to its own address" do
    sign_in_as(users(:reader))

    get "/cs-studio/account"

    # One element of that id: the new-password field, whose name is
    # `password`, has an id of its own.
    assert_select "[id=password]", count: 1
    assert_select "input#new_password[name=password]"
    assert_select "section#password[aria-labelledby=account-password]" do
      assert_select "h2#account-password", text: "Password"
      assert_select "input[name=current_password]"
    end
    assert_select "form#password-form[action='/cs-studio/account/password'] input[name=_method][value=patch]"
    assert_select "form#profile-form[action='/cs-studio/account/profile']"
  end

  test "the six cards are card frames, the password card anchored at #password and the sessions card at #sessions" do
    sign_in_as(users(:reader))

    get "/cs-studio/account"

    assert_select "turbo-frame#content .max-w-\\[560px\\] > h1", text: "Your account"
    cards = css_select("turbo-frame#content section.admin-settings-card")
    assert_equal %w[account-profile account-notes account-password passkeys recovery-codes sessions], cards.map { |card| card["aria-labelledby"] }
    # Profile and Notes are the person's, in the people pair; Password is neutral, its own key.
    assert_select "section.admin-settings-card[aria-labelledby=account-profile] .admin-settings-card__head" do
      assert_select "span.bg-ic-people-bg[aria-hidden=true] svg path[d^='M19 21v-2']"
      assert_select "h2#account-profile", text: "Profile"
      assert_select "p", count: 0
    end
    assert_select "section.admin-settings-card[aria-labelledby=account-notes] .admin-settings-card__head" do
      assert_select "span.bg-ic-people-bg[aria-hidden=true] svg path[d^='M21 15a2 2']"
      assert_select "h2#account-notes", text: "Notes"
      assert_select "p.text-small", text: "What happens in this browser when someone mentions you in a note."
    end
    assert_select "section#password.admin-settings-card.scroll-mt-6[aria-labelledby=account-password]" do
      assert_select ".admin-settings-card__head span.bg-sunken[aria-hidden=true] svg path[d^='M2.586 17.414']"
      assert_select ".admin-settings-card__head h2#account-password", text: "Password"
      assert_select ".admin-settings-card__head p.text-small", text: "You'll stay signed in here. Other sessions are signed out."
    end
    # Sessions is neutral, its own monitor and phone; its heading is the anchor its answers come back to.
    assert_select "section#account-sessions.admin-settings-card.scroll-mt-6.mt-8[aria-labelledby=sessions]" do
      assert_select ".admin-settings-card__head span.bg-sunken[aria-hidden=true] svg path[d^='M18 8V6']"
      assert_select ".admin-settings-card__head h2#sessions", text: "Sessions"
    end
    # The password form's words are keys of `admin.accounts.password`.
    assert_select "label[for=current_password]", text: "Current password"
    assert_select "label[for=new_password]", text: "New password"
    assert_select "label[for=password_confirmation]", text: "Confirm new password"
    assert_select "#password-form .admin-save-bar button[type=submit][data-password-submit]", text: "Change password"
  end

  test "a saved password is the compact ok notice and a blocked permission the warn notice" do
    put_mail_state(:working)
    sign_in_as(users(:reader))

    get "/cs-studio/account"

    # Inside the permission's status region, so the notice speaks through it and has no role of its own.
    blocked = css_select("[data-controller='admin--notes--permission'] [role=status] > div[data-admin--notes--permission-target=blocked][hidden]:not([role])").sole
    assert_equal "Blocked in this browser. Change it in the site settings of your browser.", blocked.text.strip
    assert_empty Admin::Ui::NoticeComponent.classes(:warn, size: :compact).split - blocked["class"].split
    assert_select "[data-admin--notes--permission-target=ask].rounded-card.bg-accent-tint.text-small.text-ink[hidden]", text: /This browser has not been allowed/
    allow = css_select("[data-admin--notes--permission-target=ask] button[type=button]").sole
    assert_equal "Allow in this browser", allow.text.strip
    assert_empty Admin::Ui::ButtonComponent.classes(:secondary, size: :small).split - allow["class"].split
    tertiary = Admin::Ui::ButtonComponent.classes(:tertiary, size: :small)
    assert_equal tertiary.split.sort, css_select("#password-form .admin-save-bar a[href='/cs-studio/password/new']").first["class"].split.sort

    patch "/cs-studio/account/password", params: { current_password: "password", password: "new-password-1", password_confirmation: "new-password-1" }
    follow_redirect!

    saved = css_select("#password div[role=status][tabindex='-1'][data-password-saved]").sole
    assert_equal "Password changed. Your other sessions were signed out.", saved.text.strip
    assert_empty Admin::Ui::NoticeComponent.classes(:ok, size: :compact).split - saved["class"].split
  end

  test "⌘K's Your account leads to /account" do
    sign_in_as(users(:reader))

    get "/cs-studio/jump", params: { q: "your account" }

    assert_includes response.body, "/cs-studio/account"
    assert_not_includes response.body, "/cs-studio/account/password"
  end

  # The page drawn as the password form's answer
  # says so on the Password card (the script then brings the page to it);
  # drawn for any other reason it does not.
  test "the Password card is marked as the form's answer after a save and after a refusal, and not otherwise" do
    sign_in_as(users(:reader))
    get "/cs-studio/account"
    assert_select "section#password[data-controller]", count: 0

    patch "/cs-studio/account/password", params: { current_password: "wrong", password: "new-password-1", password_confirmation: "new-password-1" }
    assert_response :unprocessable_entity
    assert_select "section#password[data-controller='admin--account--password-answer']"

    patch "/cs-studio/account/profile", params: { name: "Ada" }
    follow_redirect!
    assert_select "section#password[data-controller]", count: 0

    patch "/cs-studio/account/password", params: { current_password: "password", password: "new-password-1", password_confirmation: "new-password-1" }
    follow_redirect!
    assert_select "section#password[data-controller='admin--account--password-answer']"
    get "/cs-studio/account"
    assert_select "section#password[data-controller]", count: 0
  end

  test "a linked person's account shows the Sign-in card and Sessions, and no password, passkeys or codes" do
    with_sso do
      user = link_to_sso(users(:reader))
      sign_in_as(user)

      get "/cs-studio/account"

      assert_response :success
      assert_select "section#password h2", text: "Sign-in"
      assert_select "section#password", text: /You sign in with .+\./
      assert_select "section#account-sessions"
      assert_select "#password-form, input[type=password], #account-passkeys, #account-recovery, #account-recovery-codes", count: 0
      assert_select "form[action$='/account/passkeys'], form[action$='/account/recovery-codes'], dialog#regenerate-recovery-codes", count: 0
      assert_select "section#account-profile, #profile-form"
    end
  end

  test "a linked person's Sign-in card says the host when single sign-on is off, never a blank" do
    user = link_to_sso(users(:reader))
    sign_in_as(user)

    get "/cs-studio/account"

    assert_select "section#password", text: /You sign in with id\.example\.com\./
  end

  test "a crafted password change for a linked person is refused and changes nothing" do
    with_sso do
      user = link_to_sso(users(:reader))
      sign_in_as(user)
      digest = user.reload.password_digest

      patch "/cs-studio/account/password", params: { current_password: "password", password: "new-password-1", password_confirmation: "new-password-1" }

      assert_response :unprocessable_entity
      assert_select ".admin-error-summary[role=alert] li", text: I18n.t("admin.users.sso_linked_password", provider: OidcHelper::NAME)
      assert_equal digest, user.reload.password_digest
    end
  end

  test "an owner's account is unchanged: Password, Passkeys and Recovery codes stay" do
    with_sso do
      sign_in_as(users(:one))

      get "/cs-studio/account"

      assert_select "#password-form"
      assert_select "section#account-passkeys"
      assert_select "section#account-recovery"
      assert_select "section#password h2", text: "Password"
    end
  end
end
