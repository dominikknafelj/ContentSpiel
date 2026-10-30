require "test_helper"

class Admin::PasswordsControllerTest < ActionDispatch::IntegrationTest
  # `capture_log(REQUEST_LOGGERS)`: everything a request logs.
  include LogCapture

  ADMIN = "/#{ContentSpiel::ADMIN_PATH}".freeze

  # The suite's default mail state is "Saved, not tested", where the request
  # page is closed. This file is about the reset, so mail works for it (the
  # change is undone with the test's transaction); the tests of the closed
  # state say so themselves.
  setup do
    @user = User.take
    put_mail_state(:working)
  end

  test "new" do
    get new_admin_password_path
    assert_response :success
  end

  test "new is the request state: email field and send button, and no hint about missing mail" do
    get new_admin_password_path
    assert_select "h1", text: "Reset password"
    assert_select "label[for=email_address]", text: "Email"
    assert_select "button.bg-accent", text: "Send reset link"
    assert_select "main", text: /No outgoing mail/, count: 0
    assert_select "a", text: /Back to sign in/
  end

  # Only the REQUEST follows mail (spec "Sign-in and the reset"): a
  # bookmarked request page must not pretend to send.
  test "the request page and its POST redirect to sign-in unless mail is ready, and send nothing" do
    %i[ not_set_up untested ].each do |state|
      with_mail_state(state) do
        get new_admin_password_path
        assert_redirected_to admin_sign_in_path
        get new_admin_password_path(sent: 1)
        assert_redirected_to admin_sign_in_path
        assert_no_enqueued_emails do
          post admin_password_path, params: { email_address: @user.email_address }
        end
        assert_redirected_to admin_sign_in_path
      end
    end
  end

  test "a lapsed link met without mail lands on sign-in with the one fact" do
    with_mail_state(:untested) do
      get new_admin_password_path(expired: 1)
      assert_redirected_to admin_sign_in_path
      follow_redirect!
      assert_select "#alert", text: "This reset link has expired. Ask the site's owner to reset your password."
    end
  end

  test "a link already mailed still shows the form, checks and sets the password when mail is not ready" do
    token = @user.password_reset_token
    with_mail_state(:not_set_up) do
      get admin_edit_password_path
      assert_response :success
      post admin_check_password_path, params: { token: token }
      assert_response :no_content
      patch admin_update_password_path, params: { token: token, password: "a-new-password-1", password_confirmation: "a-new-password-1" }
      assert_redirected_to admin_sign_in_path
      assert @user.reload.authenticate("a-new-password-1")
    end
  end

  test "a reset requested for an invited address is answered as for an unknown one, and sends nothing" do
    invited = users(:reader)
    invited.update_columns(invited_at: Time.current, invite_sent_at: Time.current) # version: none (a test's setup)
    assert_no_enqueued_emails do
      post admin_password_path, params: { email_address: invited.email_address }
    end
    assert_redirected_to new_admin_password_path(sent: 1)
    unknown = response.location
    assert_no_enqueued_emails do
      post admin_password_path, params: { email_address: "nobody-here@example.test" }
    end
    assert_equal unknown, response.location
  end

  test "the expired state says one sentence for a lapsed, a used and an invalid link" do
    get new_admin_password_path(expired: "1")
    assert_select "h1", text: "This reset link has expired"
    assert_select "[role=alert]", text: "This reset link has expired. Ask for a new one."
  end

  # Handoff "Studio Password Reset": the form on the page itself (no card), the
  # site name above the heading, and a back link that underlines on hover only.
  test "every state sits directly on the page, with the site name above the heading and an ununderlined back link" do
    [ new_admin_password_path, new_admin_password_path(sent: "1"), new_admin_password_path(expired: "1"),
      admin_edit_password_path ].each do |path|
      get path
      assert_select "main div.bg-surface.border", count: 0, message: "no card on #{path}"
      assert_select ".admin-site-name + h1"
      assert_select ".admin-site-name", text: site_settings(:default).title
      assert_select "main a.underline", count: 0, message: "no always-underlined link on #{path}"
    end
    get new_admin_password_path
    assert_select "a.hover\\:underline", text: "← Back to sign in"
    assert_select "h1.text-\\[28px\\].font-semibold"
  end

  # With no address configured the mail's link can only point where the
  # request came from, so the request's origin goes along (as a String: the
  # mail is delivered by a job).
  test "create" do
    with_site_address(nil) do
      post admin_password_path, params: { email_address: @user.email_address }
      assert_enqueued_email_with queued(PasswordsMailer), :reset, args: [ @user, { origin: "http://www.example.com" } ]
      assert_redirected_to new_admin_password_path(sent: 1)

      follow_redirect!
      assert_notice "If that address belongs to an account"
    end
  end

  # With an address configured the request's origin is not handed over at
  # all: the mailer would ignore it, and a Host a client made up never
  # reaches the job's arguments.
  test "create with a site address configured hands the mailer no origin, whatever Host the request named" do
    with_site_address("https://docs.example.org") do
      post admin_password_path, params: { email_address: @user.email_address }, headers: { "Host" => "evil.example" }

      assert_enqueued_email_with queued(PasswordsMailer), :reset, args: [ @user ]
      assert_not_includes enqueued_jobs.sole.to_s, "evil.example"
    end
  end

  # In production (and every environment but development and test) the
  # request's origin is never used for the link, so it is not handed over
  # either: no mail is sent, and the page says the same words.
  test "create in production with no address configured hands over no origin, sends no mail and answers the same" do
    with_singleton_override(PasswordsMailer, :request_origin_used?, ->(*) { false }) do
      with_site_address(nil) do
        post admin_password_path, params: { email_address: @user.email_address }, headers: { "Host" => "evil.example" }

        assert_enqueued_email_with queued(PasswordsMailer), :reset, args: [ @user ]
        assert_not_includes enqueued_jobs.sole.to_s, "evil.example"
        assert_no_emails { perform_enqueued_jobs }
        assert_redirected_to new_admin_password_path(sent: 1)

        follow_redirect!
        assert_notice "If that address belongs to an account"
      end
    end
  end

  test "the mail that create enqueues links to the configured address, and without one to the request's origin" do
    with_site_address("https://docs.example.org") do
      perform_enqueued_jobs { post admin_password_path, params: { email_address: @user.email_address }, headers: { "Host" => "evil.example" } }
      assert_match %r{^https://docs\.example\.org/cs-studio/password/edit#\S+$}, ActionMailer::Base.deliveries.last.text_part.body.to_s
    end

    with_site_address(nil) do
      perform_enqueued_jobs { post admin_password_path, params: { email_address: @user.email_address }, headers: { "Host" => "here.example:3010" } }
      assert_match %r{^http://here\.example:3010/cs-studio/password/edit#\S+$}, ActionMailer::Base.deliveries.last.text_part.body.to_s
    end
  end

  test "create for an unknown user redirects but sends no mail" do
    post admin_password_path, params: { email_address: "missing-user@example.com" }
    assert_enqueued_emails 0
    assert_redirected_to new_admin_password_path(sent: 1)

    follow_redirect!
    assert_notice "If that address belongs to an account"
  end

  test "after a reset request the page says the same thing whether or not the account exists" do
    post admin_password_path, params: { email_address: users(:one).email_address }
    follow_redirect!
    known = css_select("main").text.squish
    post admin_password_path, params: { email_address: "nobody@example.com" }
    follow_redirect!
    assert_equal known, css_select("main").text.squish
    assert_match "If that address belongs to an account, we've sent a link. It expires in 15 minutes.", known
  end

  # The states are selected by exactly the value the controller redirects
  # with; any other value is just the request form.
  test "only sent=1 and expired=1 select a state" do
    get new_admin_password_path(sent: "0")
    assert_select "h1", text: "Check your email", count: 0
    get new_admin_password_path(expired: "false")
    assert_select "h1", text: "This reset link has expired", count: 0
    get new_admin_password_path(sent: "1")
    assert_select "h1", text: "Check your email"
    get new_admin_password_path(expired: "1")
    assert_select "h1", text: "This reset link has expired"
  end

  # The token is not in the address, so the page cannot know whether the
  # link is good: a bad, used or lapsed one is answered when the form is
  # sent, not before.
  test "an expired or invalid reset link shows the expired state with a way to ask again, once the form is sent" do
    patch admin_update_password_path, params: { token: "not-a-token", password: "a-new-password-1", password_confirmation: "a-new-password-1" }
    assert_redirected_to new_admin_password_path(expired: 1)

    follow_redirect!
    assert_select "h1", text: "This reset link has expired"
    assert_select "main", text: /This reset link has expired\. Ask for a new one\./
    assert_select "a", text: "Send a new link"
  end

  test "the reset form uses the password field with the meter" do
    get admin_edit_password_path
    assert_select "[data-controller='password-field'] [data-password-field-target=bar]", count: 4
  end

  # THE PAGE AS A SERVER DRAWS IT: no token and no lookup. The form is there
  # but hidden until the script has moved the token out of the address
  # (`reset-token`), the "incomplete" message is hidden beside it, and
  # someone without JavaScript is told that the page needs it.
  test "edit draws the form hidden and empty of a token, with the script's three targets and a line for no JavaScript" do
    get admin_edit_password_path
    assert_response :success

    assert_select "main [data-controller='reset-token'][data-reset-token-check-url-value='#{ADMIN}/password/check']" \
                  "[data-reset-token-expired-url-value='#{ADMIN}/password/new?expired=1']", count: 1
    assert_select "main [data-controller='reset-token']" do
      assert_select "form[hidden][method=post][action='#{ADMIN}/password'][data-reset-token-target=form]", count: 1 do
        assert_select "input[type=hidden][name=_method][value=patch]"
        assert_select "input[type=hidden][name=token][data-reset-token-target=token]", count: 1
        assert_select "input[name=token][value]:not([value=''])", count: 0
        assert_select "button[type=submit]", text: "Set password"
      end
      assert_select "div[hidden][data-reset-token-target=incomplete]", count: 1 do
        assert_select "p[role=alert]", text: "This link is incomplete. Open the link in the email again, or ask for a new one."
        assert_select "a[href='#{ADMIN}/password/new']", text: "Send a new link"
      end
      assert_select "noscript", text: /Setting a new password needs JavaScript\. Turn it on in your browser and open the link again\./
    end
  end

  test "edit reads no user: the page is the same with no account at all behind it" do
    statements = capture_sql { get admin_edit_password_path }

    assert_response :success
    assert_empty statements.grep(/"users"/)
  end

  test "edit ignores a token handed to it as a parameter: it reaches neither the form nor a redirect" do
    token = @user.password_reset_token
    get admin_edit_password_path(token: token)

    assert_response :success
    assert_not_includes response.body, token
  end

  # THE OLD ADDRESS, which mails sent before this change still carry for
  # their fifteen minutes: answered, with a redirect that names no token (a
  # server cannot hand a browser a fragment it was never sent, and must not
  # repeat the token in another address). The page then says the link is
  # incomplete.
  test "the old address redirects to the page with no token in the Location, whatever stood in its place" do
    [ @user.password_reset_token, "not-a-token", "edit", "new" ].each do |word|
      get "#{ADMIN}/password/#{word}/edit?from=mail"

      assert_response :found
      assert_equal "http://www.example.com#{ADMIN}/password/edit", response.location, word
      assert_not_includes response.body, word unless %w[edit new].include?(word)
    end
  end

  # The old PATCH is gone, and is nobody's address any more: a plain 404,
  # the same as any other address CS Studio does not have, and no password
  # changes.
  test "the old address of the form answers nothing: it is not found like any unknown address, and changes no password" do
    token = @user.password_reset_token

    assert_no_changes -> { @user.reload.password_digest } do
      patch "#{ADMIN}/password/#{token}", params: { password: "a-new-password-1", password_confirmation: "a-new-password-1" }
    end
    assert_response :not_found
    unknown = [ response.status, response.location ]
    patch "#{ADMIN}/no-such-address-here"

    assert_equal [ response.status, response.location ], unknown
    assert_not_includes response.location.to_s, token
    assert_not_includes response.body, token
  end

  test "update" do
    assert_changes -> { @user.reload.password_digest } do
      patch admin_update_password_path, params: { token: @user.password_reset_token, password: "a-new-password-1", password_confirmation: "a-new-password-1" }
      assert_redirected_to admin_sign_in_path
    end
    assert @user.reload.authenticate("a-new-password-1")

    follow_redirect!
    assert_notice "Password has been reset"
  end

  # A reset is what someone does who has lost the account to someone else:
  # every session goes, including one in the very browser that follows the
  # emailed link (`Users::UpdatePassword` ends them with the write).
  test "update ends every session of the user, a signed-in one in this browser included" do
    elsewhere = @user.sessions.create!
    sign_in_as(@user)
    here = Current.session

    patch admin_update_password_path, params: { token: @user.password_reset_token, password: "a-new-password-1", password_confirmation: "a-new-password-1" }

    assert_redirected_to admin_sign_in_path
    assert_not Session.exists?(elsewhere.id)
    assert_not Session.exists?(here.id)
  end

  test "update is audited as the user's own password change, as before" do
    assert_difference -> { Audit::Event.where(action: "user.updated", subject: @user, actor_id: @user.id).count }, 1 do
      patch admin_update_password_path, params: { token: @user.password_reset_token, password: "a-new-password-1", password_confirmation: "a-new-password-1" }
    end
  end

  # A token is good once: it is signed over the password it was mailed for.
  test "a token that has reset the password once resets nothing a second time" do
    token = @user.password_reset_token
    patch admin_update_password_path, params: { token: token, password: "a-new-password-1", password_confirmation: "a-new-password-1" }

    assert_no_changes -> { @user.reload.password_digest } do
      patch admin_update_password_path, params: { token: token, password: "a-new-password-2", password_confirmation: "a-new-password-2" }
    end
    assert_redirected_to new_admin_password_path(expired: 1)
  end

  test "a tampered, lapsed, blank or missing token, and one that is no string, changes nothing and is the expired state" do
    lapsed = @user.password_reset_token
    session = @user.sessions.create!
    good = @user.password_reset_token

    cases = bad_tokens(good)
    cases.each do |name, token|
      assert_no_changes -> { @user.reload.password_digest }, name do
        patch admin_update_password_path, params: { token: token, password: "a-new-password-1", password_confirmation: "a-new-password-1" }.compact
      end
      assert_redirected_to new_admin_password_path(expired: 1), name
    end

    travel 16.minutes do
      assert_no_changes -> { @user.reload.password_digest } do
        patch admin_update_password_path, params: { token: lapsed, password: "a-new-password-1", password_confirmation: "a-new-password-1" }
      end
      assert_redirected_to new_admin_password_path(expired: 1)
    end
    assert Session.exists?(session.id)

    follow_redirect!
    assert_notice "This reset link has expired"
  end

  test "a refused update ends no session" do
    session = @user.sessions.create!

    patch admin_update_password_path, params: { token: @user.password_reset_token, password: "a-new-password-1", password_confirmation: "another" }

    assert Session.exists?(session.id)
  end

  # A REFUSED PASSWORD is answered on the form (422), not with a redirect:
  # the page a redirect led to would have no token, and the token must not go
  # into an address to get there. It is in the hidden field of this one
  # response, to the person who sent it, and the response is kept by no
  # cache.
  test "update with non matching passwords answers the form again, with the token in its field and in no address" do
    token = @user.password_reset_token
    assert_no_changes -> { @user.reload.password_digest } do
      patch admin_update_password_path, params: { token: token, password: "long-enough-pw-1", password_confirmation: "long-enough-pw-2" }
    end

    assert_response :unprocessable_entity
    assert_nil response.location
    assert_select "#alert[role=alert]", text: "Password confirmation doesn't match Password"
    assert_select "form:not([hidden])[data-reset-token-target=form] input[type=hidden][name=token]", count: 1 do |fields|
      assert_equal token, fields.first["value"]
    end
    assert_select "div[hidden][data-reset-token-target=incomplete]"
    assert_equal 1, response.body.scan(token).size, "the token is in the response once: the field"
    assert_select "input[type=password][value]", count: 0
  end

  test "update with a blank password says so" do
    token = @user.password_reset_token
    assert_no_changes -> { @user.reload.password_digest } do
      patch admin_update_password_path, params: { token: token, password: "", password_confirmation: "" }
    end

    assert_response :unprocessable_entity
    assert_notice "Password can't be blank"
    assert_select "input[type=hidden][name=token]" do |fields|
      assert_equal token, fields.first["value"]
    end
  end

  test "update with a password that is too short answers 422 and keeps the token in the form" do
    token = @user.password_reset_token
    assert_no_changes -> { @user.reload.password_digest } do
      patch admin_update_password_path, params: { token: token, password: "short", password_confirmation: "short" }
    end

    assert_response :unprocessable_entity
    assert_select "#alert[role=alert]", text: "Use at least 12 characters."
    assert_select "input[type=hidden][name=token]" do |fields|
      assert_equal token, fields.first["value"]
    end
  end

  # The token the form came back with is still the one that was mailed: the
  # second try is the same request with a password the rule takes.
  test "the token of a refused form sets the password on the next try" do
    patch admin_update_password_path, params: { token: @user.password_reset_token, password: "short", password_confirmation: "short" }
    token = css_select("input[name=token]").first["value"]

    assert_changes -> { @user.reload.password_digest } do
      patch admin_update_password_path, params: { token: token, password: "a-new-password-1", password_confirmation: "a-new-password-1" }
    end
    assert_redirected_to admin_sign_in_path
  end

  # NO CACHE KEEPS A PAGE OF THIS FORM: the one that carries the token (the
  # 422) above all, and the empty one too, so that no cache can hand out
  # the one for the other and the browser's own back/forward cache keeps
  # neither.
  test "the form's page is kept by no cache: the empty one, the refused one and the redirects" do
    get admin_edit_password_path
    assert_equal "no-store", response.headers["Cache-Control"]

    patch admin_update_password_path, params: { token: @user.password_reset_token, password: "short", password_confirmation: "short" }
    assert_response :unprocessable_entity
    assert_equal "no-store", response.headers["Cache-Control"]

    patch admin_update_password_path, params: { token: "not-a-token", password: "a-new-password-1", password_confirmation: "a-new-password-1" }
    assert_equal "no-store", response.headers["Cache-Control"]

    get "#{ADMIN}/password/#{@user.password_reset_token}/edit"
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  # NO LOGGED LINE HOLDS THE TOKEN. In the form's body it is a parameter
  # named `token`, which `filter_parameters` masks; that is the whole flow
  # now. `REQUEST_LOGGERS` is everyone who writes during a request, at debug.
  test "nothing logged for the form's requests holds the token: accepted, refused, and with a bad password" do
    token = @user.password_reset_token

    log = capture_log(REQUEST_LOGGERS) do
      get admin_edit_password_path
      patch admin_update_password_path, params: { token: token, password: "short", password_confirmation: "short" }
      patch admin_update_password_path, params: { token: "#{token}x", password: "a-new-password-1", password_confirmation: "a-new-password-1" }
      patch admin_update_password_path, params: { token: token, password: "a-new-password-1", password_confirmation: "a-new-password-1" }
    end

    assert_redirected_to admin_sign_in_path
    assert_not_includes log, token
    assert_not_includes log, "a-new-password-1"
    # What makes this able to fail: the capture holds these requests' own
    # lines, the parameters among them, masked.
    assert_includes log, %(Started PATCH "#{ADMIN}/password")
    assert_includes log, "Processing by Admin::PasswordsController#update"
    assert_match(/Parameters: \{.*"token" ?=> ?"\[FILTERED\]"/, log)
  end

  # THE OLD LINK'S OWN REQUEST. What the application answers and writes for
  # it holds no token: the redirect's `Location`, its body, and the
  # parameters line, where `token` is masked. That its span holds none is
  # telemetry's (test/integration/opentelemetry_test.rb).
  #
  # NOT asserted, because it is not so: that the request's first log line
  # ("Started GET ...") is free of it. Rails writes the path it was asked
  # for before the router runs, and so does the proxy in front, which this
  # application cannot filter. A link of that shape exists only in a mail
  # sent before the token moved, for the fifteen minutes it is good, and no
  # installation has sent one.
  test "the old link's request is answered and logged without the token, but for the line that names the address asked for" do
    token = @user.password_reset_token

    log = capture_log(REQUEST_LOGGERS) { get "#{ADMIN}/password/#{token}/edit" }

    assert_response :found
    assert_not_includes response.location, token
    assert_not_includes response.body, token
    assert_includes log, "Processing by Admin::PasswordsController#legacy"
    assert_match(/Parameters: \{.*"token" ?=> ?"\[FILTERED\]"/, log)
    assert_includes log, "Redirected to http://www.example.com#{ADMIN}/password/edit"
    assert_equal [ %(Started GET "#{ADMIN}/password/#{token}/edit") ], log.lines.grep(/#{Regexp.escape(token)}/).map { |line| line[/\AStarted GET "[^"]+"/] }
  end

  # The request page and the form's page answer under a format too, as they
  # did before the token moved: nothing rewrites an address under
  # `<admin>/password/`.
  test "the request page and the form's page still answer with a format in their address" do
    [ "#{ADMIN}/password/new.html", "#{ADMIN}/password/edit.html" ].each do |path|
      get path
      assert_response :success, path
    end
  end

  # A good token of a user who is gone: Active Record raises RecordNotFound
  # for it (it looks the id up before it compares the signature's purpose),
  # which was a 404. It is the one answer of every token that is no good.
  test "a good token of a user deleted since is the expired state, not a 404" do
    user = User.create!(email_address: "leaving@example.com", password: "a-long-password-0")
    token = user.password_reset_token
    user.delete

    patch admin_update_password_path, params: { token: token, password: "a-new-password-1", password_confirmation: "a-new-password-1" }

    assert_redirected_to new_admin_password_path(expired: 1)
  end

  # THE EARLY CHECK (`check`): what the page's script asks once, with the
  # token in the body. A status and nothing else.
  test "check answers 204 for a token update would take, with no body, and is kept by no cache" do
    post admin_check_password_path, params: { token: @user.password_reset_token }

    assert_response :no_content
    assert_empty response.body
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_nil response.location
  end

  test "check answers 410 for every token that is no good: tampered, lapsed, used, blank, missing, no string, of a deleted user" do
    gone = User.create!(email_address: "leaving@example.com", password: "a-long-password-0")
    of_gone = gone.password_reset_token
    gone.delete
    lapsed = @user.password_reset_token
    used = @user.password_reset_token

    bad_tokens(@user.password_reset_token).merge("of a deleted user" => of_gone).each do |name, token|
      post admin_check_password_path, params: { token: token }.compact

      assert_response :gone, name
      assert_empty response.body, name
      assert_equal "no-store", response.headers["Cache-Control"], name
    end

    travel 16.minutes do
      post admin_check_password_path, params: { token: lapsed }
      assert_response :gone
    end

    patch admin_update_password_path, params: { token: used, password: "a-new-password-1", password_confirmation: "a-new-password-1" }
    assert_redirected_to admin_sign_in_path
    post admin_check_password_path, params: { token: used }
    assert_response :gone
  end

  # It is a question, not a use: the token is as good afterwards, and
  # nothing of the user, of a session or of the audit log has moved.
  test "check writes nothing: no user, no session, no audit event, no cookie, and the token still sets the password" do
    token = @user.password_reset_token
    session = @user.sessions.create!

    statements = capture_sql do
      assert_no_difference -> { Audit::Event.count } do
        assert_no_changes -> { @user.reload.attributes } do
          post admin_check_password_path, params: { token: token }
          post admin_check_password_path, params: { token: "#{token}x" }
        end
      end
    end

    assert_empty statements.grep(/\A\s*(INSERT|UPDATE|DELETE)/i)
    assert_nil response.headers["Set-Cookie"], "a signed-out check sets no cookie"
    assert Session.exists?(session.id)

    patch admin_update_password_path, params: { token: token, password: "a-new-password-1", password_confirmation: "a-new-password-1" }
    assert_redirected_to admin_sign_in_path
  end

  # It tells nobody more than update would: two answers, and the same one
  # for everything that is wrong.
  test "check's answers are two, and every bad token's answer is the same response" do
    answers = bad_tokens(@user.password_reset_token).values.map do |token|
      post admin_check_password_path, params: { token: token }.compact
      [ response.status, response.body, response.headers.to_h.except("x-request-id", "x-runtime", "server-timing") ]
    end

    assert_equal 1, answers.uniq.size
  end

  test "nothing logged for a check holds the token, good or bad" do
    token = @user.password_reset_token

    log = capture_log(REQUEST_LOGGERS) do
      post admin_check_password_path, params: { token: token }
      post admin_check_password_path, params: { token: "#{token}x" }
    end

    assert_not_includes log, token
    assert_includes log, %(Started POST "#{ADMIN}/password/check")
    assert_includes log, "Processing by Admin::PasswordsController#check"
    assert_match(/Parameters: \{.*"token" ?=> ?"\[FILTERED\]"/, log)
    assert_includes log, "Completed 204"
    assert_includes log, "Completed 410"
  end

  # The request form's limit, counted on its own. The test environment's
  # cache keeps nothing, so the counter is put in the store's place for the
  # block: what is tested is the declaration (ten, this action, a bare 429)
  # and that the limit comes before the token is looked at.
  test "check is limited like the request form: the eleventh in three minutes is a bare 429, whatever the token" do
    counts = Hash.new(0)
    counter = ->(key, amount = 1, **) { counts[key] += amount }

    with_singleton_override(Admin::PasswordsController.cache_store, :increment, counter) do
      10.times do
        post admin_check_password_path, params: { token: @user.password_reset_token }
        assert_response :no_content
      end
      post admin_check_password_path, params: { token: @user.password_reset_token }

      assert_response :too_many_requests
      assert_empty response.body
      assert_equal 1, counts.size
      assert_match(/check/, counts.keys.sole)

      # Counted apart from the request form's own limit.
      post admin_password_path, params: { email_address: "nobody@example.com" }
      assert_redirected_to new_admin_password_path(sent: 1)
    end
  end

  # FORGERY PROTECTION is off in the test environment, so it is switched on
  # here: the form's PATCH and the script's check are refused without the
  # page's token and taken with it. (A refused check is not a 410, so the
  # script shows the form and the form's own request decides.)
  test "with forgery protection on, the form and the check are refused without the page's token and taken with it" do
    with_forgery_protection do
      token = @user.password_reset_token
      get admin_edit_password_path
      csrf = css_select("meta[name=csrf-token]").first["content"]

      assert_no_changes -> { @user.reload.password_digest } do
        patch admin_update_password_path, params: { token: token, password: "a-new-password-1", password_confirmation: "a-new-password-1" }
      end
      assert_response :unprocessable_entity

      post admin_check_password_path, params: { token: token }
      assert_response :unprocessable_entity

      post admin_check_password_path, params: { token: token }, headers: { "X-CSRF-Token" => csrf }
      assert_response :no_content

      assert_changes -> { @user.reload.password_digest } do
        patch admin_update_password_path, params: { token: token, password: "a-new-password-1", password_confirmation: "a-new-password-1", authenticity_token: csrf }
      end
      assert_redirected_to admin_sign_in_path
    end
  end

  private

    # A mail is queued with the fingerprint of the mail settings it was asked
    # under (`ApplicationMailer.queue`), a param of the mailer.
    def queued(mailer) = mailer.with(fingerprint: MailSettings.current.fingerprint)

    def assert_notice(text)
      assert_select "main", /#{text}/
    end

    # Every way a token handed over is not a good one, but for time: what
    # only the clock or a use makes bad is each test's own.
    def bad_tokens(good)
      { "tampered" => "#{good[0..-6]}AAAAA", "another's words" => "invalid token", "blank" => "", "missing" => nil,
        "a list" => [ good ], "a hash" => { "a" => good } }
    end

    def with_forgery_protection
      was = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      yield
    ensure
      ActionController::Base.allow_forgery_protection = was
    end
end
