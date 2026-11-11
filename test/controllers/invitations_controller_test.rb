require "test_helper"

class InvitationsControllerTest < ActionDispatch::IntegrationTest
  test "the invitation page answers the expired sentence, signed out and never cached" do
    get admin_invitation_path

    assert_response :success
    assert_includes response.body, "This invite has expired. Ask the person who invited you to send a new one."
    assert_includes response.headers["Cache-Control"], "no-store"
  end

  test "an invitation refuses a leaked password and draws the form again" do
    invitation = open_invitation("dana@example.com", name: "Dana")
    token = invitation.generate_token_for(:accept)

    with_leaked_password_check(leaked: [ "correct horse battery" ]) do
      assert_no_difference "User.count" do
        post admin_accept_invitation_path, params: { token: token, name: "Dana", password: "correct horse battery", password_confirmation: "correct horse battery" }
      end
    end

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /#{Regexp.escape("This password is in a list of leaked passwords, so it isn't safe to use. Choose another one.")}/
    assert_select "input[type=hidden][name=token]" do |fields|
      assert_equal token, fields.first["value"]
    end
    assert_not_includes response.body, "correct horse battery"
    assert invitation.reload.open?
  end

  # One answer for every link that is no good, whatever is wrong with it: a
  # bot holding a guessed or an old token learns nothing of which
  # invitations exist, were resent or were withdrawn.
  test "check and update answer a tampered, a lapsed, a resent and a withdrawn token the same: status, body and no-store" do
    good = open_invitation("dana@example.com", name: "Dana").generate_token_for(:accept)
    lapsed = open_invitation("lapsed@example.com")
    lapsed_token = travel_to(Time.current - Invitation::VALID_FOR.to_i.seconds - 60) { lapsed.generate_token_for(:accept) }
    resent = open_invitation("resent@example.com")
    resent_token = resent.generate_token_for(:accept)
    resent.update!(sent_at: 1.minute.from_now)
    withdrawn = open_invitation("gone@example.com")
    withdrawn_token = withdrawn.generate_token_for(:accept)
    withdrawn.destroy!

    tokens = { "tampered" => "#{good[0..-6]}AAAAA", "lapsed" => lapsed_token, "resent" => resent_token, "withdrawn" => withdrawn_token }
    answers = tokens.transform_values do |token|
      post admin_check_invitation_path, params: { token: token }
      check = [ response.status, response.body, response.headers["Cache-Control"] ]
      post admin_accept_invitation_path, params: { token: token, name: "Dana", password: "a-new-long-password-1", password_confirmation: "a-new-long-password-1" }
      update = [ response.status, without_page_secrets(response.body), response.headers["Cache-Control"] ]
      [ check, update ]
    end

    assert_equal 1, answers.values.uniq.size, answers.keys.zip(answers.values.map(&:hash)).inspect
    check, update = answers.values.first
    assert_equal [ 410, "", "no-store" ], check
    assert_equal [ 422, "no-store" ], update.values_at(0, 2)
  end

  # The check names the invitation's own address and name, for its form, and
  # nothing else; the used and expired pages name nobody.
  test "an invitation's answers name no account but the invitation's own" do
    dana = open_invitation("dana@example.com", name: "Dana")
    token = dana.generate_token_for(:accept)
    others = User.pluck(:email_address)

    post admin_check_invitation_path, params: { token: token }
    assert_equal({ "email_address" => "dana@example.com", "name" => "Dana" }, response.parsed_body)

    bodies = []
    post admin_accept_invitation_path, params: { token: "#{token}x", name: "Dana", password: "a-new-long-password-1", password_confirmation: "a-new-long-password-1" }
    bodies << response.body
    User.create!(email_address: "dana@example.com", name: "Dana Account", password: "a-new-long-password-1")
    post admin_accept_invitation_path, params: { token: token, name: "Dana", password: "a-new-long-password-1", password_confirmation: "a-new-long-password-1" }
    assert_response :unprocessable_entity
    bodies << response.body

    bodies.each do |body|
      (others + [ "dana@example.com", "Dana Account" ]).each { |named| assert_not_includes body, named }
    end
  end

  private

  def without_page_secrets(body) = body.gsub(/(name="authenticity_token" value=|name="csrf-token" content=|nonce=)"[^"]*"/, '\\1""')
end
