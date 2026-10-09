require "test_helper"

# "Change my password" (access-control design spec §3.3 "Any user may change
# their own password", §5 "reachable by every user from the account menu").
class Admin::AccountsTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
  end

  test "every signed-in user reaches it from the account menu" do
    sign_in_as(users(:reader))

    get "/cs-studio/api_tokens"
    assert_select "a[href='/cs-studio/account/password']", text: /Change password/

    get "/cs-studio/account/password"
    assert_response :success
    assert_select "input[type=password][name=current_password]"
  end

  test "signed out, it redirects to sign-in" do
    get "/cs-studio/account/password"
    assert_redirected_to "/cs-studio/sign-in"
  end

  test "a wrong current password fails and changes nothing" do
    sign_in_as(users(:reader))

    patch "/cs-studio/account/password", params: { current_password: "wrong", password: "new-password-1", password_confirmation: "new-password-1" }

    assert_response :unprocessable_entity
    assert_select ".admin-error-summary[role=alert] li", text: "That's not your current password."
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
    sign_in_as(users(:reader))

    get "/cs-studio/account/password"

    assert_select "h1 + p", text: "You'll stay signed in here. Other sessions are signed out."
    assert_select "#password-form .admin-save-bar a[href='/cs-studio/password/new']", text: "Forgot your current password?"
    assert_select "#profile-form .admin-save-bar a", text: "Forgot your current password?", count: 0
    assert_select "#notes-form .admin-save-bar a", text: "Forgot your current password?", count: 0
    # One footer per form: the name, the Notes switches, the password.
    assert_select ".admin-save-bar", count: 3
  end

  test "visiting the reset flow signed in signs nobody out" do
    user = users(:reader)
    sign_in_as(user)
    session_id = Current.session.id

    get "/cs-studio/password/new"

    assert_response :success
    assert Session.exists?(session_id)
    get "/cs-studio/account/password"
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

    assert_redirected_to "/cs-studio/account/password"
    follow_redirect!
    assert_select "[role=status]", text: /Password changed/
    assert user.reload.authenticate("new-password-1")
    assert_not Session.exists?(other_session.id)
    assert Session.exists?(current_session.id)
    # Still signed in here: the next request is served, not sent to sign-in.
    get "/cs-studio/account/password"
    assert_response :success

    event = Audit::Event.find_by!(action: "user.updated", subject: user)
    assert_not_includes event.attributes.to_json, "new-password-1"
    assert_not_includes event.attributes.to_json, user.password_digest
  end

  test "a user saves their own name" do
    user = users(:reader)
    sign_in_as(user)

    patch "/cs-studio/account/profile", params: { name: "Ada" }

    assert_redirected_to "/cs-studio/account/password"
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
    assert_includes response.body, "Name saved."
    assert_includes response.body, "Ada &lt;i&gt;L&lt;/i&gt;"
    assert_not_includes response.body, "<i>L</i>"
  end

  # The format is decided without `respond_to`: the name is saved by then.
  test "a client that takes neither a stream nor HTML is redirected, never told 406 about a save that happened" do
    sign_in_as(users(:one))
    patch admin_account_profile_path, params: { name: "Json Client" }, headers: { "Accept" => "application/json" }

    assert_redirected_to "/cs-studio/account/password"
    assert_equal "Json Client", users(:one).reload.name
  end

  test "signed out, saving a name redirects to sign-in" do
    patch "/cs-studio/account/profile", params: { name: "Ada" }
    assert_redirected_to "/cs-studio/sign-in"
  end

  # --- the Notes switches (notes spec §6.4, D18, D19) ------------------------------

  test "the account screen has the two Notes switches in a form of their own with a save bar, and saving keeps the screen" do
    sign_in_as(users(:reader))
    get "/cs-studio/account/password"

    assert_select "form#notes-form[action='/cs-studio/account/notifications'][data-controller='admin--save-bar']" do
      assert_select "h2", text: "Notes"
      assert_select "input[type=checkbox][name=notes_sound][role=switch][checked]"
      assert_select "input[type=checkbox][name=notes_desktop][role=switch]:not([checked])"
      assert_select "label", text: "Play a sound when I'm mentioned"
      assert_select "label", text: "Show a desktop notification when I'm mentioned"
      # The permission is this browser's: drawn hidden, shown by the script.
      assert_select "[data-controller='admin--notes-permission'] [hidden] button[type=button]:not([name])", text: "Allow in this browser"
      assert_select "[data-controller='admin--notes-permission'] [hidden]", text: "Blocked in this browser. Change it in the site settings of your browser."
      assert_select "[data-admin--save-bar-target=bar] button[type=submit][form=notes-form]", text: "Save"
    end
    assert_select "body[data-admin--notes-alert-sound-value=true][data-admin--notes-alert-desktop-value=false][data-admin--notes-alert-person-value='#{users(:reader).id}']"
    # Changing the password draws the screen again: it waits for the name and for the switches.
    assert_select "form#password-form[data-admin--save-bar-after-value='profile-form notes-form']"

    patch "/cs-studio/account/notifications", params: { notes_sound: "0", notes_desktop: "1" }, headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" }

    assert_response :ok
    assert_select "turbo-stream[action=append][target=toasts]"
    assert_match "Notification settings saved.", response.body
    assert_equal [ false, true ], users(:reader).reload.then { |user| [ user.notes_sound, user.notes_desktop ] }

    get "/cs-studio/account/password"
    assert_select "input[name=notes_sound]:not([checked])"
    assert_select "input[name=notes_desktop][checked]"
    assert_select "body[data-admin--notes-alert-sound-value=false][data-admin--notes-alert-desktop-value=true]"
  end

  test "without Turbo, saving the switches is a redirect back to the screen; a switch left out is off" do
    sign_in_as(users(:reader))

    patch "/cs-studio/account/notifications", params: { notes_desktop: "1" }

    assert_redirected_to "/cs-studio/account/password"
    assert_equal [ false, true ], users(:reader).reload.then { |user| [ user.notes_sound, user.notes_desktop ] }
    follow_redirect!
    assert_match "Notification settings saved.", response.body
  end

  # Only ever the signed-in person's own: the request names no user.
  test "the switches are saved for whoever is signed in, whatever else the request names" do
    sign_in_as(users(:two))

    patch "/cs-studio/account/notifications", params: { notes_sound: "0", notes_desktop: "1", id: users(:reader).id, user_id: users(:reader).id }

    assert_equal [ false, true ], users(:two).reload.then { |user| [ user.notes_sound, user.notes_desktop ] }
    assert_equal [ true, false ], users(:reader).reload.then { |user| [ user.notes_sound, user.notes_desktop ] }
  end

  test "signed out, saving the switches redirects to sign-in and writes nothing" do
    patch "/cs-studio/account/notifications", params: { notes_sound: "0", notes_desktop: "1" }

    assert_redirected_to "/cs-studio/sign-in"
    assert User.where(notes_sound: false).or(User.where(notes_desktop: true)).none?
  end
end
