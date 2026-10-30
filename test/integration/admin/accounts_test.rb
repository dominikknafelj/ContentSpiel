require "test_helper"

# "Your account", the screen (the notes handoff's decision 25), whose third
# card is "Change my password" (access-control design spec §3.3 "Any user may change
# their own password", §5 "reachable by every user from the account menu").
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
    # In the Password card, not above the cards (the handoff's decision 43).
    assert_select "#password .admin-error-summary[role=alert] li", text: "That's not your current password."
    assert_select ".admin-error-summary", count: 1
    assert_select "#current_password-errors", text: "That's not your current password."
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

  test "the screen promises what the code does, and links the reset flow from the card's footer" do
    put_mail_state(:working)
    sign_in_as(users(:reader))

    get "/cs-studio/account"

    # The handoff's decision 25: the page is "Your account"; its cards are
    # Profile, Notes and Password, in that order; and the promise about
    # sessions stands directly under the Password card's title.
    assert_select "title", text: "Your account"
    assert_select "h1", text: "Your account", count: 1
    assert_select "turbo-frame#content h2", count: 0
    assert_equal %w[Profile Notes Password], css_select("turbo-frame#content section h3").map { |heading| heading.text.strip }
    assert_select "form#profile-form section", count: 2
    assert_select "form#password-form section[aria-labelledby=account-password]" do
      assert_select "h3#account-password + p", text: "You'll stay signed in here. Other sessions are signed out."
      assert_select "input[type=password]", count: 3
    end
    # The Password card's footer is the card's own and sits inside it, under
    # a line (notes handoff, decision 34); the first form's stays under its
    # two cards, as it was.
    assert_select "form#password-form section[aria-labelledby=account-password] > .admin-save-bar.admin-save-bar--contained.border-t:last-child button[type=submit]", text: "Change password"
    assert_select "form#password-form section ~ .admin-save-bar", count: 0
    assert_select "form#profile-form > section ~ .admin-save-bar.sticky:not(.admin-save-bar--contained) button[type=submit]", text: "Save"
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

  test "a success changes the password and signs out other sessions only" do
    user = users(:reader)
    other_session = user.sessions.create!
    sign_in_as(user)
    current_session = Current.session

    patch "/cs-studio/account/password", params: { current_password: "password", password: "new-password-1", password_confirmation: "new-password-1" }

    assert_redirected_to "/cs-studio/account#password"
    follow_redirect!
    # Said in the card, and by no toast (the handoff's decision 43).
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

  # --- the Notes switches (notes spec §6.4, D18, D19; handoff decision 13) ----------

  test "the name and the two Notes switches are one form with one footer, and saving keeps the screen" do
    sign_in_as(users(:reader))
    get "/cs-studio/account"

    assert_select "form#profile-form[action='/cs-studio/account/profile'][data-controller='admin--saving--save-bar']" do
      # Decisions 19 and 20: "Your account", then two cards of one width,
      # Profile and Notes, and one footer under both, whose button is "Save".
      assert_select "section.max-w-\\[560px\\]", count: 2
      assert_select "section[aria-labelledby=account-profile] h3#account-profile", text: "Profile"
      assert_select "section[aria-labelledby=account-profile] label[for=name]", text: "Your name"
      assert_select "section[aria-labelledby=account-profile] input[name=name]"
      assert_select "section[aria-labelledby=account-notes] h3#account-notes", text: "Notes"
      assert_select "section ~ [data-admin--saving--save-bar-target=bar] button[type=submit]", text: "Save"
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

  # The handoff's decision 38: the page is "Your account", and its address
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
      assert_select "h3#account-password", text: "Password"
      assert_select "input[name=current_password]"
    end
    assert_select "form#password-form[action='/cs-studio/account/password'] input[name=_method][value=patch]"
    assert_select "form#profile-form[action='/cs-studio/account/profile']"
  end

  test "⌘K's Your account leads to /account" do
    sign_in_as(users(:reader))

    get "/cs-studio/jump", params: { q: "your account" }

    assert_includes response.body, "/cs-studio/account"
    assert_not_includes response.body, "/cs-studio/account/password"
  end

  # The handoff's decision 42: the page drawn as the password form's answer
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
end
