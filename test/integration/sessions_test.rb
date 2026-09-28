require "test_helper"

class SessionsTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "admin@example.com", password: "password123")
  end

  # The only reason anyone signs in at all is to reach CS Studio -- the public
  # site needs no authentication of its own, so a "cold" sign-in (one that
  # didn't arrive here via `request_authentication` redirecting from some
  # other protected page, which is the only thing that ever records a
  # return_to_after_authenticating) has nothing more useful to send the
  # visitor back to than the admin itself.
  test "signing in with no page to return to redirects to CS Studio" do
    post admin_sign_in_url, params: { email_address: "admin@example.com", password: "password123" }

    assert_redirected_to admin_root_path
  end

  # The normal case: signing in *because* a protected page demanded it sends
  # the visitor on to the page they actually asked for, not just the admin
  # root.
  test "signing in after being redirected from a protected page returns there" do
    get "/cs-studio/settings"
    assert_redirected_to "/cs-studio/sign-in"

    post "/cs-studio/sign-in", params: { email_address: "admin@example.com", password: "password123" }

    assert_redirected_to "/cs-studio/settings"
  end

  test "signing in with invalid credentials redirects back to the sign-in form" do
    post admin_sign_in_url, params: { email_address: "admin@example.com", password: "wrong" }

    assert_redirected_to admin_sign_in_url
  end

  # Access-control design spec §4.3 "Sessions" and Review Focus 5: a
  # failed sign-in names the email that was tried and no user, and nothing
  # of the password -- not under any key, not as a value.
  test "a failed sign-in records session.failed with the email and no password" do
    post admin_sign_in_url, params: { email_address: "admin@example.com", password: "wrong-secret" }

    event = Audit::Event.find_by!(action: "session.failed")
    assert_equal({ "email_address" => "admin@example.com" }, event.metadata)
    assert_nil event.user_id
    assert_nil event.actor
    assert_equal "admin", event.channel
    assert_not_includes event.attributes.to_json, "wrong-secret"
    assert_not_includes event.metadata.keys.join, "passw"
  end

  # Final fix wave (Minor 4): a password typed into the email box (no "@")
  # isn't stored at all, and a long value is cut to an address's length.
  test "a failed sign-in stores no email that isn't one, and truncates a long one" do
    post admin_sign_in_url, params: { email_address: "hunter2-my-password", password: "x" }
    assert_equal({}, Audit::Event.find_by!(action: "session.failed").metadata)
    assert_not_includes Audit::Event.find_by!(action: "session.failed").attributes.to_json, "hunter2"

    long = "#{"a" * 400}@example.com"
    post admin_sign_in_url, params: { email_address: long, password: "x" }
    stored = Audit::Event.where(action: "session.failed").order(:id).last.metadata["email_address"]
    assert_equal 254, stored.length
    assert_equal long.first(254), stored
  end

  test "signing in and out records session.created and session.destroyed as the user" do
    post admin_sign_in_url, params: { email_address: "admin@example.com", password: "password123" }
    created = Audit::Event.find_by!(action: "session.created")
    assert_equal @user, created.actor
    assert_equal @user, created.subject
    assert_not_includes created.attributes.to_json, "password123"

    delete admin_sign_out_url
    destroyed = Audit::Event.find_by!(action: "session.destroyed")
    assert_equal @user, destroyed.actor
    assert_equal @user, destroyed.subject
  end
end
