require "test_helper"

class Admin::UsersTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
  end

  test "the list shows every user" do
    get "/cs-studio/users"
    assert_response :success
    assert_select "#" + ActionView::RecordIdentifier.dom_id(users(:one))
    assert_select "#" + ActionView::RecordIdentifier.dom_id(users(:two))
  end

  test "never renders a password digest" do
    get "/cs-studio/users"
    assert_not_includes response.body, users(:one).password_digest
  end

  test "creating a user" do
    assert_difference -> { User.count }, 1 do
      post "/cs-studio/users", params: { user: {
        email_address: "new@example.com", password: "password12345", password_confirmation: "password12345"
      } }
    end

    assert_response :redirect
    follow_redirect!
    assert_response :success
    user = User.find_by!(email_address: "new@example.com")
    assert user.authenticate("password12345")
  end

  test "creating a user with mismatched confirmation fails" do
    assert_no_difference -> { User.count } do
      post "/cs-studio/users", params: { user: {
        email_address: "new@example.com", password: "password12345", password_confirmation: "nope"
      } }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "doesn&#39;t match"
  end

  test "a refused create shows the error summary with a link to each field and marks the field invalid" do
    post "/cs-studio/users", params: { user: { email_address: users(:one).email_address, password: "short", password_confirmation: "short" } }

    assert_response :unprocessable_entity
    assert_select ".admin-error-summary[role=alert]", text: /2 things need fixing/
    assert_select ".admin-error-summary a[href='#user_email_address']", text: "Email address has already been taken"
    assert_select ".admin-error-summary a[href='#user_password']", text: "Use at least 12 characters."
    assert_select "input#user_email_address[aria-invalid=true]"
  end

  test "creating a user with an email already taken (case-insensitively) fails" do
    assert_no_difference -> { User.count } do
      post "/cs-studio/users", params: { user: {
        email_address: users(:one).email_address.upcase, password: "password12345", password_confirmation: "password12345"
      } }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "has already been taken"
  end

  # The edit form is an explicit-save form with a leave guard that only sees
  # Turbo Drive visits: a link inside the content frame would discard typed
  # changes without asking, so the one there breaks out of the frame.
  test "the Activity link on the edit screen leaves the content frame" do
    get "/cs-studio/users/#{users(:two).id}/edit"
    assert_select "a[data-turbo-frame='_top']", text: "Activity"
    # The footer's Save is server-rendered enabled (only the controller ever
    # disables it), so the form can be submitted without JavaScript too.
    assert_select "#user-form .admin-save-bar button[type=submit]:not([disabled])", text: "Save user"
    assert_select "#user-form noscript", count: 0
  end

  test "editing a user's email without touching the password" do
    user = users(:two)
    digest_before = user.password_digest

    patch "/cs-studio/users/#{user.id}", params: { user: { email_address: "changed@example.com" } }

    assert_response :redirect
    user.reload
    assert_equal "changed@example.com", user.email_address
    assert_equal digest_before, user.password_digest
  end

  test "changing a user's password" do
    user = users(:two)

    patch "/cs-studio/users/#{user.id}", params: { user: {
      password: "brand-new-password", password_confirmation: "brand-new-password"
    } }

    assert_response :redirect
    assert user.reload.authenticate("brand-new-password")
  end

  test "deleting another user" do
    assert_difference -> { User.count }, -1 do
      delete "/cs-studio/users/#{users(:two).id}"
    end

    assert_response :redirect
    follow_redirect!
    assert_response :success
    assert_includes response.body, "User deleted"
  end

  test "refuses to delete the last owner" do
    assert_no_difference -> { User.count } do
      delete "/cs-studio/users/#{users(:one).id}"
    end

    assert_response :redirect
    follow_redirect!
    assert_includes response.body, "The last owner can&#39;t be deleted"
  end

  test "deleting yourself signs you out" do
    # users(:one) is the sole owner (test/fixtures/users.yml) and can't be
    # deleted at all, last-owner or not -- deletes as :two instead, who
    # isn't an owner, so nothing here is exercising the last-owner guard.
    sign_in_as(users(:two))

    delete "/cs-studio/users/#{users(:two).id}"

    assert_redirected_to admin_sign_in_path
    follow_redirect!
    assert_response :success

    # The session is really gone, not just redirected past -- a request
    # against a signed-in-only page bounces back to sign-in instead of
    # succeeding.
    get "/cs-studio/users"
    assert_redirected_to admin_sign_in_path
  end

  # --- Groups and owner (access-control design spec §5 "Users module") ---------

  test "a user's groups are saved from the edit form" do
    user = users(:reader)

    get "/cs-studio/users/#{user.id}/edit"
    assert_select "input[type=checkbox][name='user[group_ids][]'][value='#{access_control_groups(:read_only).id}'][checked]"

    patch "/cs-studio/users/#{user.id}", params: { user: {
      email_address: user.email_address, group_ids: [ "", access_control_groups(:editor).id ]
    } }

    assert_response :redirect
    assert_equal [ access_control_groups(:editor).id ], user.reload.group_ids
  end

  test "the list shows each user's groups and owners" do
    get "/cs-studio/users"

    assert_select "#" + ActionView::RecordIdentifier.dom_id(users(:one)), text: /Owner/
    assert_select "#" + ActionView::RecordIdentifier.dom_id(users(:reader)), text: /Read only/
  end

  test "an owner sees the owner zone; a non-owner neither sees it nor changes the flag" do
    get "/cs-studio/users/#{users(:reader).id}/edit"
    assert_select ".admin-owner-zone button", text: "Make owner…"
    assert_select "#user-form input[name='user[owner]']", count: 0

    sign_in_as(users(:two))
    get "/cs-studio/users/#{users(:reader).id}/edit"
    assert_select ".admin-owner-zone", count: 0
    assert_select "input[name='user[owner]']", count: 0

    # A forged owner field on the ordinary form is no part of it: the save is an ordinary one.
    # The 403 for a non-owner is the owner endpoint's (`users_editor_test.rb`).
    patch "/cs-studio/users/#{users(:reader).id}", params: { user: { email_address: "renamed@example.com", owner: "1" } }
    assert_response :redirect
    assert_equal "renamed@example.com", users(:reader).reload.email_address
    assert_not users(:reader).owner?
    assert_not Audit::Event.exists?(action: "access.denied")
  end

  test "the owner zone and the delete zone are disabled for the last owner, with the reason; demoting them is refused" do
    get "/cs-studio/users/#{users(:one).id}/edit"
    assert_select ".admin-owner-zone button[disabled]", text: "Remove owner rights…"
    assert_select ".admin-owner-zone", text: /one@example.com is the only owner, so their owner rights can't be removed\./
    assert_select ".admin-delete-zone button[disabled]", text: "Delete user…"
    assert_select ".admin-delete-zone", text: /one@example.com is the only owner, so they can't be deleted\./
    assert_select "dialog#owner-user-#{users(:one).id}", count: 0
    assert_select "#user-form input[name='user[owner]']", count: 0
  end

  test "a forged user[owner] on the ordinary form from an owner changes nothing about the flag" do
    patch "/cs-studio/users/#{users(:reader).id}", params: { user: { email_address: users(:reader).email_address, owner: "1" } }

    assert_response :redirect
    assert_not users(:reader).reload.owner?
    assert_not Audit::Event.exists?(action: "user.owner_changed")

    patch "/cs-studio/users/#{users(:one).id}", params: { user: { email_address: users(:one).email_address, owner: "0" } }

    assert_response :redirect
    assert users(:one).reload.owner?
  end

  # --- Fix round 1 (I1): only users whose rights are a subset of yours ------

  test "a user manager can't take over an Admin member, but can manage an Author member" do
    managers = AccessControl::Group.create!(name: "User managers")
    %w[users.manage posts.read posts.create media.upload pages.read].each do |key|
      AccessControl::Grant.create!(group: managers, permission: key, scope: {})
    end
    AccessControl::Grant.create!(group: managers, permission: "posts.edit", scope: { "own" => true })
    AccessControl::Membership.create!(user: users(:editor_branch), group: managers)
    sign_in_as(users(:editor_branch))

    admin_member = users(:two)
    digest = admin_member.password_digest
    patch "/cs-studio/users/#{admin_member.id}", params: { user: { email_address: admin_member.email_address, password: "taken-over-1", password_confirmation: "taken-over-1" } }
    assert_response :forbidden
    patch "/cs-studio/users/#{admin_member.id}", params: { user: { email_address: "mine@example.com" } }
    assert_response :forbidden
    assert_no_difference -> { User.count } do
      delete "/cs-studio/users/#{admin_member.id}"
    end
    admin_member.reload
    assert_equal digest, admin_member.password_digest
    assert_equal "two@example.com", admin_member.email_address
    assert Audit::Event.exists?(action: "access.denied", subject_type: "User", subject_id: admin_member.id)

    author = users(:author)
    patch "/cs-studio/users/#{author.id}", params: { user: { email_address: "author2@example.com", password: "reset-pass-1", password_confirmation: "reset-pass-1" } }
    assert_response :redirect
    assert_equal "author2@example.com", author.reload.email_address
    assert author.authenticate("reset-pass-1")
    assert_difference -> { User.count }, -1 do
      delete "/cs-studio/users/#{author.id}"
    end
  end

  test "group boxes the actor can't assign are disabled, keeping a ticked one" do
    managers = AccessControl::Group.create!(name: "User managers")
    AccessControl::Grant.create!(group: managers, permission: "users.manage", scope: {})
    AccessControl::Grant.create!(group: managers, permission: "posts.read", scope: {})
    AccessControl::Grant.create!(group: managers, permission: "pages.read", scope: {})
    AccessControl::Membership.create!(user: users(:editor_branch), group: managers)
    sign_in_as(users(:editor_branch))

    get "/cs-studio/users/#{users(:reader).id}/edit"

    assert_select "input[type=checkbox][name='user[group_ids][]'][value='#{access_control_groups(:admin).id}'][disabled]"
    assert_select "input[type=checkbox][name='user[group_ids][]'][value='#{access_control_groups(:read_only).id}']:not([disabled])"
  end

  test "an owner change through the owner endpoint leaves an open user form stale" do
    user = users(:reader)
    get "/cs-studio/users/#{user.id}/edit"
    open_form_base = Nokogiri::HTML(response.body).at_css("input[name=base_updated_at]")["value"]

    patch "/cs-studio/users/#{user.id}/owner", params: { owner: "1" }
    assert user.reload.owner?

    patch "/cs-studio/users/#{user.id}", params: { user: { name: "From the old tab" }, base_updated_at: open_form_base }
    assert_response :conflict
    assert_not_equal "From the old tab", user.reload.name
  end

  test "a save on a stale base is refused with the banner, the typed values kept and nothing written" do
    user = users(:author)
    get "/cs-studio/users/#{user.id}/edit"
    stale = Nokogiri::HTML(response.body).at_css("input[name=base_updated_at]")["value"]
    assert stale.present?

    Users::Save.call(user, attributes: { name: "Renamed elsewhere" }, actor: nil)

    assert_no_difference -> { Audit::Event.count } do
      patch "/cs-studio/users/#{user.id}", params: { user: { name: "Typed name", email_address: "typed@example.com", group_ids: [ "", access_control_groups(:read_only).id.to_s ] }, base_updated_at: stale }
    end

    assert_response :conflict
    assert_includes response.body, "This user was changed elsewhere since you opened this screen. Reload to see the latest — your changes are still in the form."
    assert_select "#user_name[value=?]", "Typed name"
    assert_select "#user_email_address[value=?]", "typed@example.com"
    assert_select "input[name=base_updated_at][value=?]", stale
    assert_select "#user-form[data-admin--save-bar-dirty-value=true]", 1, "the typed values count as unsaved"
    assert_equal "Renamed elsewhere", user.reload.name
    assert_not_equal "typed@example.com", user.email_address
  end

  test "a blank base is not stale, and the form as rendered carries a base" do
    user = users(:author)
    get "/cs-studio/users/#{user.id}/edit"
    assert_select "#user-form input[name=base_updated_at][value]"

    patch "/cs-studio/users/#{user.id}", params: { user: { email_address: user.email_address }, base_updated_at: "" }
    assert_response :see_other
  end
end
