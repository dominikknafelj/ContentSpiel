require "test_helper"

# The invited person's page (mail spec "Invites" and "Security rules",
# design answer M5): `<admin>/invitation#<token>`, drawn without the token,
# which the page's script moves from the fragment into the form's body; its
# early `check` and the accept form. Built as the reset page is
# (test/controllers/admin/passwords_controller_test.rb, which says why).
class InvitationsTest < ActionDispatch::IntegrationTest
  include LogCapture

  ADMIN = "/#{ContentSpiel::ADMIN_PATH}".freeze
  PAGE = "#{ADMIN}/invitation".freeze
  CHECK = "#{ADMIN}/invitation/check".freeze
  PASSWORD = "a-new-long-password-1".freeze
  EXPIRED = "This invite has expired. Ask the person who invited you to send a new one.".freeze
  USED = "This invite has already been used.".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @dana = open_invitation("dana@example.com", name: "Dana")
    @token = @dana.generate_token_for(:accept)
  end

  def accept(token: @token, name: "Dana Doe", password: PASSWORD, confirmation: PASSWORD)
    post PAGE, params: { token: token, name: name, password: password, password_confirmation: confirmation }
  end

  test "the page is drawn without a token or a person: the form, the two states and a line for no JavaScript, hidden for the script" do
    get PAGE, params: { token: @token }
    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_not_includes response.body, @token
    assert_not_includes response.body, "dana@example.com"

    assert_select "[data-controller=invitation-token][data-invitation-token-check-url-value=?]", CHECK do
      assert_select "h1", /\AWelcome to \S.*\z/
      assert_select "form[action=?][method=post][hidden]", PAGE do
        assert_select "input[type=hidden][name=token][value]", count: 0
        assert_select "[data-invitation-token-target=line][hidden]", /Set a password to finish your account for/
        assert_select "input[name=name]"
        assert_select "input[name=password]"
        assert_select "input[name=password_confirmation]"
        assert_select "button[type=submit]", "Set password and sign in"
      end
      assert_select "[data-invitation-token-target=expired][hidden]", EXPIRED
      assert_select "[data-invitation-token-target=used][hidden]", /#{USED}/ do
        assert_select "a[href=?]", "#{ADMIN}/sign-in", "Sign in"
      end
      assert_select "noscript"
    end
  end

  test "the accept page's four answers: the form, expired (also for withdrawn and invalid, one sentence), used with a Sign in link" do
    # The form: the check names whose link it is.
    post CHECK, params: { token: @token }
    assert_response :ok
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal({ "email_address" => "dana@example.com", "name" => "Dana" }, response.parsed_body)

    # Expired: lapsed, replaced by a resend, withdrawn, invalid, none, not a string -- one answer.
    # A token lapses seven days after it was MADE (the mail makes it when it
    # is sent), so the lapsed one is made that long ago. Seconds, not days:
    # a span of days can cross a clock change.
    lapsed = open_invitation("lapsed@example.com", sent_at: 8.days.ago)
    lapsed_token = travel_to(Time.current - Invitation::VALID_FOR.to_i.seconds - 60) { lapsed.generate_token_for(:accept) }
    resent = open_invitation("resent@example.com")
    old = resent.generate_token_for(:accept)
    resent.update!(sent_at: 1.minute.from_now)
    withdrawn = open_invitation("gone@example.com")
    gone = withdrawn.generate_token_for(:accept)
    withdrawn.destroy!

    bad = { "lapsed" => lapsed_token, "resent" => old, "withdrawn" => gone,
            "tampered" => "#{@token[0..-6]}AAAAA", "a reset token" => users(:one).password_reset_token,
            "blank" => "", "missing" => nil, "a list" => [ @token ] }
    answers = bad.map do |label, token|
      post CHECK, params: { token: token }.compact
      assert_response :gone, label
      assert_empty response.body, label

      accept(token: token)
      assert_response :unprocessable_entity, label
      assert_select "[data-controller=invitation-token]", false, label
      assert_select "form", false, label
      [ label, css_select("main").text.squish ]
    end.to_h
    assert_equal 1, answers.values.uniq.size, answers.inspect
    assert_includes answers.values.first, EXPIRED

    # Used: the check's 409, and the form's own request draws the used state.
    accept
    assert_redirected_to admin_root_path
    post CHECK, params: { token: @token }
    assert_response :conflict
    reset!
    accept
    assert_response :unprocessable_entity
    assert_select "[data-invitation-token-target=used]:not([hidden])", /#{USED}/ do
      assert_select "a[href=?]", "#{ADMIN}/sign-in", "Sign in"
    end
    assert_select "[data-invitation-token-target=expired][hidden]"
  end

  # The review of the rework, Important 1: an account made for the address
  # closes the invitation, so deleting that account later does not bring the
  # old link back to life.
  test "invite, an account made on New user, the account deleted: the old link is expired and creates nothing" do
    sign_in_as(users(:one))
    post "#{ADMIN}/users", params: { user: { email_address: "dana@example.com", password: PASSWORD, password_confirmation: PASSWORD } }
    account = User.find_by!(email_address: "dana@example.com")
    assert_not Invitation.exists?(@dana.id)

    delete "#{ADMIN}/users/#{account.id}"
    assert_not User.exists?(account.id)
    reset!

    post CHECK, params: { token: @token }
    assert_response :gone
    assert_no_difference [ -> { User.count }, -> { Session.count }, -> { AccessControl::Membership.count } ] do
      accept
    end
    assert_response :unprocessable_entity
    assert_select "[data-invitation-token-target=expired]:not([hidden])"
  end

  # An account made for the address meanwhile (the New user form) is the
  # person's way in: the link is used, and accepting makes no second account.
  test "a link whose address has an account by now is used: the check's 409 and the used state, and nothing is written" do
    User.create!(email_address: "dana@example.com", password: PASSWORD)

    post CHECK, params: { token: @token }
    assert_response :conflict

    assert_no_difference [ -> { User.count }, -> { Audit::Event.count } ] do
      accept
    end
    assert_response :unprocessable_entity
    assert_select "[data-invitation-token-target=used]:not([hidden])", /#{USED}/
    assert @dana.reload.open?
  end

  test "accepting creates the account, signs the person in on the dashboard with Your account is ready." do
    accept
    assert_redirected_to admin_root_path
    assert_equal "Your account is ready.", flash[:notice]

    # The sign-in is recorded as sign-in records it: the user's own event.
    signed_in = Audit::Event.where(action: "session.created").sole
    account = User.find_by!(email_address: "dana@example.com")
    assert_equal [ account, account.id ], [ signed_in.subject, signed_in.user_id ]
    assert_empty signed_in.metadata
    assert_equal account.id, Users::LastSignIn.for([ account ]).keys.sole

    assert @dana.reload.accepted?
    user = User.find_by!(email_address: "dana@example.com")
    assert_equal user, @dana.user
    assert_equal "Dana Doe", user.name
    assert user.authenticate(PASSWORD)
    assert_equal 1, user.sessions.count

    follow_redirect!
    assert_response :success
    assert_select "body", /Your account is ready\./
  end

  # Plan ruling T9a: the browser is the invited person's from here on, so a
  # session that was signed in in it is ended on the server, not only
  # replaced in the cookie.
  test "accepting in a browser where someone else is signed in ends their session first" do
    sign_in_as(users(:one))
    other = Current.session
    assert Session.exists?(other.id)

    accept
    assert_redirected_to admin_root_path
    assert_not Session.exists?(other.id), "the other person's session is gone"
    assert_equal 1, @dana.reload.user.sessions.count
    follow_redirect!
    assert_response :success
    assert_select "body", /Your account is ready\./
  end

  test "the page takes no name from an address, and the form takes a name only as a string" do
    get PAGE, params: { name: "Mallory" }
    assert_response :success
    assert_not_includes response.body, "Mallory"
    assert_select "input[name=name]:not([value])"

    post PAGE, params: { token: @token, name: { "a" => "b" }, password: PASSWORD, password_confirmation: PASSWORD }
    assert_response :bad_request
    assert @dana.reload.open?
    assert_nil User.find_by(email_address: "dana@example.com")
  end

  test "a refused password draws the form again with the token, the address and the typed name, and the next try takes it" do
    accept(name: "Dana D", password: "short", confirmation: "short")
    assert_response :unprocessable_entity
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_select "#alert", /12 characters/
    assert_select "form:not([hidden])" do
      assert_select "input[type=hidden][name=token][value=?]", @token
      assert_select "[data-invitation-token-target=line]:not([hidden]) strong", "dana@example.com"
      assert_select "input[name=name][value=?]", "Dana D"
      assert_select "input[name=password][value]", count: 0
    end
    assert @dana.reload.open?
    assert_nil User.find_by(email_address: "dana@example.com")

    accept(password: PASSWORD, confirmation: "something-else-123")
    assert_response :unprocessable_entity
    assert @dana.reload.open?

    accept
    assert_redirected_to admin_root_path
  end

  test "no token in any logged line or Location of the accept requests, and every answer no-store" do
    log = capture_log(REQUEST_LOGGERS) do
      get PAGE
      assert_equal "no-store", response.headers["Cache-Control"]
      post CHECK, params: { token: @token }
      assert_equal "no-store", response.headers["Cache-Control"]
      post CHECK, params: { token: "#{@token}x" }
      assert_equal "no-store", response.headers["Cache-Control"]
      accept(password: "short", confirmation: "short")
      assert_equal "no-store", response.headers["Cache-Control"]
      accept(token: "#{@token}x")
      assert_equal "no-store", response.headers["Cache-Control"]
      accept
      assert_equal "no-store", response.headers["Cache-Control"]
      assert_not_includes response.headers["Location"].to_s, @token
      accept
      assert_equal "no-store", response.headers["Cache-Control"]
    end

    assert_not_includes log, @token
    assert_not_includes log, PASSWORD
    # What makes this able to fail: the capture holds these requests' own
    # lines, the parameters among them, masked.
    assert_includes log, %(Started POST "#{PAGE}")
    assert_includes log, "Processing by InvitationsController#update"
    assert_includes log, "Processing by InvitationsController#check"
    assert_match(/Parameters: \{.*"token" ?=> ?"\[FILTERED\]"/, log)
  end

  test "check writes nothing: no user, no session, no audit event, no cookie, and the link still works" do
    assert_no_difference [ -> { User.count }, -> { Session.count }, -> { Audit::Event.count } ] do
      assert_no_changes -> { @dana.reload.attributes } do
        post CHECK, params: { token: @token }
      end
    end
    assert_nil response.cookies["session_id"]

    accept
    assert_redirected_to admin_root_path
  end

  test "check is limited like the reset page's: the eleventh in three minutes is a bare 429" do
    counts = Hash.new(0)
    counter = ->(key, amount = 1, **) { counts[key] += amount }

    with_singleton_override(InvitationsController.cache_store, :increment, counter) do
      10.times do
        post CHECK, params: { token: @token }
        assert_response :ok
      end
      post CHECK, params: { token: @token }
      assert_response :too_many_requests
      assert_empty response.body
    end
  end
end
