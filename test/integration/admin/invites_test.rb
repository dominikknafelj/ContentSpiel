require "test_helper"

# Invites on the Users screen (mail spec "Invites", design answer M4): the
# "Invite person" button and its dialog, the refusals the dialog shows, the
# invited row (its pill, its dates, its menu), resend and withdraw, and the
# limit of ten invites per person in three minutes. The rules themselves are
# the services' (test/services/invitations/); this is what the
# screen does with them.
class Admin::InvitesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  USERS = "/cs-studio/users".freeze
  DIALOG = "dialog##{Admin::UsersScreen::InviteDialogComponent::DIALOG_ID}".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
  end

  test "Invite person is offered to users.manage only when mail is ready" do
    # The suite's default: saved, not tested. An owner is told why, and where.
    get USERS
    assert_response :success
    assert_select "button", text: "Invite person", count: 0
    assert_select DIALOG, count: 0
    assert_select "[data-invites-need-mail]", text: /Invites need mail\./ do
      assert_select "a[href=?]", "/cs-studio/settings#mail", text: "Set up mail →"
    end

    with_mail_state(:working) do
      get USERS
      assert_select "button[data-admin--ui--dialog-id-param=?]", "invite-person", text: "Invite person"
      assert_select DIALOG do
        assert_select "h2", "Invite a person"
        assert_select "input[type=email][name='user[email_address]'][required]"
        assert_select "input[name='user[name]']"
        assert_select "input[type=checkbox][name='user[group_ids][]']", AccessControl::Group.count
        assert_select "button[type=submit][form=invite-person-form]", "Send invite"
        assert_select "button", "Cancel"
      end
      assert_select "[data-invites-need-mail]", count: 0
    end

    # Someone with users.manage who is no owner: the button when mail works,
    # and no word about mail when it doesn't (mail is the owners' to set up).
    sign_out
    sign_in_as(users(:two))
    get USERS
    assert_response :success
    assert_select "[data-invites-need-mail]", count: 0
    assert_select "button", text: "Invite person", count: 0
    with_mail_state(:failed) do
      get USERS
      assert_select "button", text: "Invite person"
    end

    # Without users.manage there is no Users screen at all.
    sign_out
    sign_in_as(users(:reader))
    get USERS
    assert_response :forbidden
  end

  test "sending an invite: an invitation and no user, the mail queued, and the list says so" do
    with_mail_state(:working) do
      assert_enqueued_jobs 1 do
        post "/cs-studio/invites", params: { user: { email_address: " Dana@Example.com ", name: "Dana",
          group_ids: [ "", access_control_groups(:editor).id ] } }
      end
      assert_redirected_to USERS
      follow_redirect!
      assert_select "#toasts, [role=status], body", /Invite sent to dana@example\.com\./

      dana = Invitation.open.find_by!(email_address: "dana@example.com")
      assert_not User.exists?(email_address: "dana@example.com")
      assert_equal [ access_control_groups(:editor) ], dana.groups.to_a
      assert_select "##{ActionView::RecordIdentifier.dom_id(dana)}[data-invited]" do
        assert_select "[data-invite-state=open]", "Invited"
        assert_select "[data-column=groups]", /Editor/
        sent = I18n.l(dana.sent_at, format: :"admin.short")
        expires = I18n.l(dana.expires_at, format: :"admin.short")
        assert_select "[data-invite-dates]", "Invited #{sent} · expires #{expires}"
        assert_select "[data-invite-menu] button", text: "Resend invite"
        assert_select "[data-invite-menu] button", text: "Withdraw invite…"
        assert_select "dialog#withdraw-invite-#{dana.id}", text: /Withdraw the invite to dana@example\.com\? The link stops working\./
      end
    end
  end

  test "an invitation with no name is listed by its address among the users, opens no editor, and an expired one says so instead of its dates" do
    fresh = open_invitation("fresh@example.com")
    lapsed = open_invitation("lapsed@example.com", sent_at: 8.days.ago)
    accepted = open_invitation("accepted@example.com").tap { |invitation| invitation.update!(accepted_at: Time.current) }

    get USERS
    assert_select "##{ActionView::RecordIdentifier.dom_id(fresh)}" do
      assert_select "span.font-medium", "fresh@example.com"
      assert_select "a", count: 0
      assert_select "[data-invite-state=open]", "Invited"
    end
    assert_select "##{ActionView::RecordIdentifier.dom_id(accepted)}", count: 0
    expected = (User.all.to_a + [ fresh, lapsed ]).sort_by(&:email_address).map { |row| ActionView::RecordIdentifier.dom_id(row) }
    assert_equal expected, css_select(".admin-users-list li").map { |row| row["id"] }, "the invitations stand among the users in the order of the address"
    assert_select "##{ActionView::RecordIdentifier.dom_id(lapsed)}" do
      assert_select "[data-invite-state=expired]", "Invite expired"
      assert_select "[data-invite-dates]", count: 0
      assert_select "[data-invite-menu]"
    end
    # A user who can sign in has no menu and no pill.
    assert_select "##{ActionView::RecordIdentifier.dom_id(users(:reader))}" do
      assert_select "[data-invite-menu]", count: 0
      assert_select "[data-invite-state]", count: 0
    end
  end

  test "the dialog's errors, with Resend on an already invited address" do
    invited = open_invitation("dana@example.com")

    with_mail_state(:working) do
      assert_no_difference -> { Invitation.count } do
        post "/cs-studio/invites", params: { user: { email_address: "Reader@Example.com ", name: "Someone" } }
      end
      assert_response :unprocessable_entity
      assert_select "#{DIALOG}[data-admin--ui--dialog-open-on-load]" do
        assert_select "#invite_email_address_error", /\ASomeone with this address already has an account\.\s*\z/
        assert_select "input#invite_email_address[aria-invalid=true]"
        assert_select "input#invite_name[value=?]", "Someone"
        assert_select "#invite-person-resend", count: 0
      end

      post "/cs-studio/invites", params: { user: { email_address: "DANA@example.com", group_ids: [ access_control_groups(:editor).id ] } }
      assert_response :unprocessable_entity
      assert_select "#{DIALOG}[data-admin--ui--dialog-open-on-load]" do
        assert_select "#invite_email_address_error", /This address is already invited\./ do
          assert_select "button[type=submit][form=invite-person-resend]", "Resend"
        end
        assert_select "form#invite-person-resend[action=?]", "/cs-studio/invites/#{invited.id}/resend"
        # The Resend form is not the invite form: Enter still sends the invite.
        assert_select "form#invite-person-form form", count: 0
        assert_select "form#invite-person-form button[type=submit]:not([form=invite-person-resend])", count: 0
        assert_select "input[name='user[group_ids][]'][value='#{access_control_groups(:editor).id}'][checked]"
      end

      post "/cs-studio/invites", params: { user: { email_address: "" } }
      assert_response :unprocessable_entity
      assert_select "#invite_email_address_error", /Email address can't be blank/
    end

    # Mail stopped working since the page was drawn: one line at the top.
    post "/cs-studio/invites", params: { user: { email_address: "new@example.com" } }
    assert_response :unprocessable_entity
    assert_select "#{DIALOG}[data-admin--ui--dialog-open-on-load] p[role=alert]", "Invites need mail."
    assert_not Invitation.exists?(email_address: "new@example.com")
  end

  test "resend gives the invitation a new link, and withdraw deletes it; an accepted invitation is not found" do
    dana = open_invitation("dana@example.com", sent_at: 2.days.ago)
    accepted = open_invitation("accepted@example.com").tap { |invitation| invitation.update!(accepted_at: Time.current) }

    with_mail_state(:working) do
      assert_enqueued_jobs 1 do
        post "/cs-studio/invites/#{dana.id}/resend"
      end
      assert_redirected_to USERS
      assert_equal "New invite sent to dana@example.com.", flash[:notice]
      assert_in_delta Time.current, dana.reload.sent_at, 5

      post "/cs-studio/invites/#{accepted.id}/resend"
      assert_response :not_found
    end

    assert_no_difference -> { Invitation.count } do
      delete "/cs-studio/invites/#{accepted.id}"
    end
    assert_response :not_found

    assert_no_difference -> { User.count } do
      assert_difference -> { Invitation.count }, -1 do
        delete "/cs-studio/invites/#{dana.id}"
      end
    end
    assert_redirected_to USERS
    assert_equal "Invite to dana@example.com withdrawn.", flash[:notice]
  end

  test "someone who may not manage users cannot invite, resend or withdraw" do
    dana = open_invitation("dana@example.com")
    sign_out
    sign_in_as(users(:reader))

    with_mail_state(:working) do
      assert_no_difference -> { Invitation.count } do
        post "/cs-studio/invites", params: { user: { email_address: "x@example.com" } }
        delete "/cs-studio/invites/#{dana.id}"
      end
      post "/cs-studio/invites/#{dana.id}/resend"
      assert_response :forbidden
    end
  end

  # The test environment's cache keeps nothing, so the counter is put in the
  # store's place for the block: what is tested is the declaration (ten, by
  # the signed-in person, create only).
  test "10 invites per person per 3 minutes" do
    counts = Hash.new(0)
    counter = ->(key, amount = 1, **) { counts[key] += amount }

    with_mail_state(:working) do
      with_singleton_override(Admin::InvitesController.cache_store, :increment, counter) do
        10.times do |index|
          post "/cs-studio/invites", params: { user: { email_address: "person#{index}@example.com" } }
          assert_redirected_to USERS
        end

        assert_no_difference -> { Invitation.count } do
          post "/cs-studio/invites", params: { user: { email_address: "eleventh@example.com" } }
        end
        assert_redirected_to USERS
        assert_equal "Try again later.", flash[:alert]
        assert_equal 1, counts.size
        assert_match(/#{users(:one).id}\z/, counts.keys.sole)

        # Another person counts on their own.
        sign_out
        sign_in_as(users(:two))
        post "/cs-studio/invites", params: { user: { email_address: "eleventh@example.com" } }
        assert_equal "Invite sent to eleventh@example.com.", flash[:notice]
        assert_equal 2, counts.size
        two = counts.keys.find { |key| key.end_with?(":#{users(:two).id}") }
        assert_equal 1, counts[two]
      end
    end
  end

  # Plan ruling T9a: a resend sends an invite mail too, so it is counted in
  # the invites' one bucket; a withdrawal sends nothing and is not counted.
  test "resend counts in the invites' bucket of ten, and withdraw counts nothing" do
    counts = Hash.new(0)
    counter = ->(key, amount = 1, **) { counts[key] += amount }
    dana = open_invitation("dana@example.com", sent_at: 1.day.ago)
    lee = open_invitation("lee@example.com")

    with_mail_state(:working) do
      with_singleton_override(Admin::InvitesController.cache_store, :increment, counter) do
        post "/cs-studio/invites", params: { user: { email_address: "person@example.com" } }
        post "/cs-studio/invites/#{dana.id}/resend"
        assert_equal "New invite sent to dana@example.com.", flash[:notice]
        assert_equal 1, counts.size, "create and resend share one key"
        key = counts.keys.sole
        assert_equal 2, counts[key]

        delete "/cs-studio/invites/#{lee.id}"
        assert_equal "Invite to lee@example.com withdrawn.", flash[:notice]
        assert_equal({ key => 2 }, counts)

        8.times { post "/cs-studio/invites/#{dana.id}/resend" }
        assert_equal 10, counts[key]

        # The eleventh, a resend or an invite, is refused and sends nothing.
        assert_no_changes -> { dana.reload.sent_at } do
          assert_no_enqueued_jobs do
            post "/cs-studio/invites/#{dana.id}/resend"
          end
        end
        assert_equal "Try again later.", flash[:alert]
        assert_no_difference -> { Invitation.count } do
          post "/cs-studio/invites", params: { user: { email_address: "another@example.com" } }
        end
        assert_equal "Try again later.", flash[:alert]
      end
    end
  end

  # An invitation is no user and no member: a group's members, its member
  # picker and every other list of people know nothing of it until it is
  # accepted (`Invitations::Accept` makes the memberships).
  test "an open invitation is in no group's members until it is accepted" do
    open_invitation("dana@example.com", groups: [ access_control_groups(:editor) ])

    get "/cs-studio/groups/#{access_control_groups(:editor).id}/edit"
    assert_response :success
    assert_select ".admin-group-members", text: /dana@example\.com/, count: 0
    assert_select ".admin-group-members", text: /Invited/, count: 0
  end
end
