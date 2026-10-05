require "test_helper"

class Admin::UsersScreen::DeleteZoneComponentTest < ViewComponent::TestCase
  def zone(user, own: false, last_owner: false)
    with_request_url("/cs-studio/users/#{user.id}/edit") do
      render_inline Admin::UsersScreen::DeleteZoneComponent.new(user: user, own: own, last_owner: last_owner)
    end
  end

  test "another user: a danger-text trigger and the dialog naming them, with the solid danger confirm" do
    zone(users(:two))

    assert_selector "h2", text: "Delete user"
    assert_selector "button.text-danger-ink[data-admin--dialog-id-param='delete-user-#{users(:two).id}'][data-admin--pending-lock-target=control]", text: "Delete user…"
    assert_selector "dialog#delete-user-#{users(:two).id}", visible: :all do
      assert_selector "dialog", text: "Delete two@example.com?", visible: :all
      assert_selector "dialog", text: "They can't sign in any more and their AI tokens stop working. Their pages, posts and media stay; posts they wrote are left without an author.", visible: :all
      assert_selector "form[action='/cs-studio/users/#{users(:two).id}'] input[name=_method][value=delete]", visible: :all
      assert_selector "button.bg-danger[type=submit]", text: "Delete user", visible: :all
    end
  end

  test "your own account: the dialog says it signs you out" do
    zone(users(:two), own: true)
    assert_selector "dialog p", text: "This is your own account — deleting it signs you out.", visible: :all
    assert_no_selector "dialog p", text: "AI tokens", visible: :all
  end

  test "the dialog names the stored name, not an edited one" do
    user = users(:two)
    user.update!(name: "Tara Two")
    user.name = "Unsaved"
    zone(user)
    assert_selector "dialog", text: "Delete Tara Two?", visible: :all
  end

  test "the last owner: disabled, with the reason, and no dialog" do
    zone(users(:one), last_owner: true)

    assert_selector "button[disabled]", text: "Delete user…"
    assert_text "one@example.com is the only owner, so they can't be deleted."
    assert_no_selector "dialog", visible: :all
  end
end

class Admin::UsersScreen::DeleteZonePreviewsTest < ViewComponent::TestCase
  def preview(name)
    with_request_url("/cs-studio/users/1/edit") { render_preview(name, from: Admin::UsersScreen::DeleteZoneComponentPreview) }
  end

  test "another_user preview names the user" do
    preview(:another_user)
    assert_selector "dialog", text: "Delete reader@example.com?", visible: :all
    assert_selector "button:not([disabled])", text: "Delete user…"
  end

  test "own_account preview says it signs you out" do
    preview(:own_account)
    assert_selector "dialog", text: "Delete mara@example.com?", visible: :all
    assert_selector "dialog", text: "deleting it signs you out", visible: :all
  end

  test "last_owner preview is disabled with the named reason" do
    preview(:last_owner)
    assert_selector "button[disabled]", text: "Delete user…"
    assert_text "mara@example.com is the only owner, so they can't be deleted."
  end
end
