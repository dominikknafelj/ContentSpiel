require "application_system_test_case"

# Invites as people take them: an owner invites someone from the Users
# screen, the invited person opens the mailed link (its token after a "#", which the page's script
# moves into the form and out of the address), sets a password, lands on
# the dashboard signed in with the account accepting made, and can sign in
# with it afterwards; and an invitation's row menu, which stands over the
# users' stretched row links, resends and withdraws.
class Admin::InvitesSystemTest < ApplicationSystemTestCase
  include ActionMailer::TestHelper

  PASSWORD = "a-new-long-password-1".freeze
  FORM = "form[data-invitation-token-target=form]".freeze
  OPEN = "#{FORM}:not([hidden]):not([aria-busy])".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    # Invites are offered only while mail works (undone with the test).
    put_mail_state(:working)
    sign_in_via_form(users(:one))
  end

  def row(record) = "##{ActionView::RecordIdentifier.dom_id(record)}"

  def address = page.evaluate_script("window.location.href")

  test "inviting, accepting from the mailed link, and signing in" do
    visit admin_users_path
    await_admin_controllers
    press "Invite person…"

    within("dialog#invite-person") do
      fill_in "Email", with: "dana@example.com"
      fill_in "Name", with: "Dana"
      find("label[data-group-card='#{access_control_groups(:editor).id}']").click
    end
    # The job that delivers the mail runs in the server's thread, at once.
    perform_enqueued_jobs do
      within("dialog#invite-person") { press "Send invite" }
      assert_text "Invite sent to dana@example.com."
    end
    invitation = Invitation.open.find_by!(email_address: "dana@example.com")
    within(row(invitation)) do
      assert_text "Dana"
      assert_text "Invited"
    end

    link = ActionMailer::Base.deliveries.last.text_part.body.to_s[%r{https?://\S+}]
    token = link.split("#", 2).last
    assert_match %r{/cs-studio/invitation#\S+\z}, link

    # The invited person, in a browser of their own.
    Capybara.reset_session!
    visit link
    assert_selector OPEN
    assert_text "Set a password to finish your account for dana@example.com"
    assert_equal "Dana", find_field("Name").value
    assert_equal link.split("#", 2).first, address, "the address bar holds neither the # nor the token"
    assert_not_includes page.evaluate_script("document.documentElement.outerHTML"), "##{token}"

    fill_in "Password", with: PASSWORD
    fill_in "Confirm password", with: PASSWORD
    press "Set password and sign in"

    assert_selector "nav[aria-label='Modules']", wait: 15
    assert_text "Your account is ready."
    assert_current_path admin_root_path
    assert invitation.reload.accepted?
    dana = User.find_by!(email_address: "dana@example.com")
    assert_equal [ access_control_groups(:editor) ], dana.groups.to_a

    # The link is used now: it says so, with the way to sign in.
    Capybara.reset_session!
    visit link
    assert_text "This invite has already been used."
    assert_no_selector FORM
    press "Sign in"
    assert_selector "h1", text: "Sign in"

    sign_in_via_form(dana, password: PASSWORD)
  end

  test "a link that is no good says the invite has expired, with no form" do
    Capybara.reset_session!
    visit "#{admin_invitation_path}#not-a-token"
    assert_text "This invite has expired. Ask the person who invited you to send a new one."
    assert_no_selector FORM

    visit admin_invitation_path
    assert_text "This invite has expired. Ask the person who invited you to send a new one."
    assert_no_selector FORM
  end

  test "an invitation's menu opens over its row, Resend and Withdraw work, and a press on the menu never opens an editor" do
    dana = open_invitation("dana@example.com", sent_at: 2.days.ago)
    was_sent = dana.sent_at
    menu = "button[aria-label='Actions for dana@example.com']"

    visit_screen admin_users_path
    # Tab goes from a user's name, the row's one stop, to the next row's menu.
    page.execute_script("document.querySelector(\"#{row(users(:author))} a.admin-row-link\").focus()")
    page.driver.browser.keyboard.type(:Tab)
    assert_equal "Actions for dana@example.com", page.evaluate_script("document.activeElement.getAttribute('aria-label')")

    within(row(dana)) do
      assert_text "Invited"
      # A native click: it fails when anything stands over the button.
      find(menu).click
      assert_selector "#{menu}[aria-expanded=true]"
      assert_selector "[role=menu]", visible: true
    end
    assert_current_path admin_users_path
    assert_selector "h1", text: "Users"
    within(row(dana)) { press "Resend invite" }
    assert_text "New invite sent to dana@example.com."
    assert_operator dana.reload.sent_at, :>, was_sent

    within(row(dana)) do
      find("button[aria-label='Actions for dana@example.com']").click
      press "Withdraw invite…"
    end
    within("dialog#withdraw-invite-#{dana.id}") do
      assert_text "Withdraw the invite to dana@example.com? The link stops working."
      press "Withdraw invite"
    end
    assert_text "Invite to dana@example.com withdrawn."
    assert_no_selector row(dana)
    assert_not Invitation.exists?(dana.id)

    # A user's row is pressed anywhere: its link's cover reaches the whole
    # row, its Edit at the far end too. A press on the point where Edit stands.
    verb = page.evaluate_script(<<~JS)
      (() => { const box = document.querySelector("#{row(users(:two))} .admin-row-verb").getBoundingClientRect()
        return [ box.left + box.width / 2, box.top + box.height / 2 ] })()
    JS
    assert page.evaluate_script("document.elementFromPoint(#{verb.join(', ')}).matches('#{row(users(:two))} a.admin-row-link')"),
      "the row link's cover does not reach Edit"
    page.driver.browser.mouse.click(x: verb.first, y: verb.last)
    assert_selector "h1", text: users(:two).name_or_email
  end
end
