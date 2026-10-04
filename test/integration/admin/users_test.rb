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

  test "creating a user with an email already taken (case-insensitively) fails" do
    assert_no_difference -> { User.count } do
      post "/cs-studio/users", params: { user: {
        email_address: users(:one).email_address.upcase, password: "password12345", password_confirmation: "password12345"
      } }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "has already been taken"
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

  test "an owner sees the owner toggle; a non-owner neither sees nor changes it" do
    get "/cs-studio/users/#{users(:reader).id}/edit"
    assert_select "input[type=checkbox][name='user[owner]']"

    sign_in_as(users(:two))
    get "/cs-studio/users/#{users(:reader).id}/edit"
    assert_select "input[name='user[owner]']", count: 0

    patch "/cs-studio/users/#{users(:reader).id}", params: { user: { email_address: users(:reader).email_address, owner: "1" } }
    assert_response :forbidden
    assert_not users(:reader).reload.owner?
  end

  test "the toggle is disabled for the last owner, and demoting them is refused" do
    get "/cs-studio/users/#{users(:one).id}/edit"
    assert_select "input[type=checkbox][name='user[owner]'][disabled][checked]"
    assert_select "input[type=hidden][name='user[owner]']", count: 0

    patch "/cs-studio/users/#{users(:one).id}", params: { user: { email_address: users(:one).email_address, owner: "0" } }
    assert_response :unprocessable_entity
    assert_includes response.body, "can&#39;t demote the last owner"
    assert users(:one).reload.owner?
  end

  test "an owner promotes another user" do
    patch "/cs-studio/users/#{users(:reader).id}", params: { user: { email_address: users(:reader).email_address, owner: "1" } }

    assert_response :redirect
    assert users(:reader).reload.owner?
    assert Audit::Event.exists?(action: "user.owner_changed", subject_type: "User", subject_id: users(:reader).id)
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
end
