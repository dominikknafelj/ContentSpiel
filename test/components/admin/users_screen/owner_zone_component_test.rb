require "test_helper"

class Admin::UsersScreen::OwnerZoneComponentTest < ViewComponent::TestCase
  def zone(user, last_owner: false)
    with_request_url("/cs-studio/users/#{user.id}/edit") do
      render_inline Admin::UsersScreen::OwnerZoneComponent.new(user: user, last_owner: last_owner)
    end
  end

  test "for a non-owner: the explanation, Make owner… and its dialog with the primary confirm" do
    zone(users(:two))

    assert_text "Owners can do everything, whatever their groups, and are the only ones who can change who is an owner."
    assert_selector ".admin-owner-zone[data-controller='admin--saving--pending-lock']"
    assert_selector "button[data-action='admin--ui--dialog#open'][data-admin--ui--dialog-id-param='owner-user-#{users(:two).id}'][data-admin--saving--pending-lock-target=control]", text: "Make owner…"
    assert_selector "dialog#owner-user-#{users(:two).id}", visible: :all do
      assert_selector "dialog", text: "Make two@example.com an owner?", visible: :all
      assert_selector "dialog", text: "Owners have every permission, including managing other owners and removing your owner rights.", visible: :all
      assert_selector "form[action='/cs-studio/users/#{users(:two).id}/owner'] input[name=_method][value=patch]", visible: :all
      assert_selector "form input[name=owner][value='1']", visible: :all
      assert_selector "button.bg-accent[type=submit]", text: "Make owner", visible: :all
    end
    assert_no_selector "dialog button.bg-danger", visible: :all
  end

  test "for an owner: Remove owner rights… and its dialog" do
    other = User.create!(email_address: "owner2@example.com", password: "password12345", owner: true)
    zone(other)

    assert_selector "button[data-admin--saving--pending-lock-target=control]:not([disabled])", text: "Remove owner rights…"
    assert_selector "dialog#owner-user-#{other.id}", visible: :all do
      assert_selector "dialog", text: "Remove owner rights from owner2@example.com?", visible: :all
      assert_selector "dialog", text: "They keep their groups and the permissions those give.", visible: :all
      assert_selector "form input[name=owner][value='0']", visible: :all
      assert_selector "button[type=submit]", text: "Remove owner rights", visible: :all
    end
  end

  test "for the last owner the button is disabled with the reason, and there is no dialog" do
    zone(users(:one), last_owner: true)

    assert_selector "button[disabled]", text: "Remove owner rights…"
    assert_text "one@example.com is the only owner, so their owner rights can't be removed."
    assert_no_selector "dialog", visible: :all
  end

  test "the hint a pending change shows is there, hidden" do
    zone(users(:two))
    assert_selector "[data-admin--saving--pending-lock-target=hint][hidden]", visible: :all
  end
end

class Admin::UsersScreen::OwnerZonePreviewsTest < ViewComponent::TestCase
  # The previews' own examples (unsaved users): each must show its named state with a real name.
  def preview(name)
    with_request_url("/cs-studio/users/1/edit") { render_preview(name, from: Admin::UsersScreen::OwnerZoneComponentPreview) }
  end

  test "non_owner preview: a named Make owner… dialog" do
    preview(:non_owner)
    assert_selector "button", text: "Make owner…"
    assert_selector "dialog", text: "Make reader@example.com an owner?", visible: :all
  end

  test "owner preview: Remove owner rights… for a named owner" do
    preview(:owner)
    assert_selector "button:not([disabled])", text: "Remove owner rights…"
    assert_selector "dialog", text: "Remove owner rights from mara@example.com?", visible: :all
  end

  test "last_owner preview: disabled with the named reason" do
    preview(:last_owner)
    assert_selector "button[disabled]", text: "Remove owner rights…"
    assert_text "mara@example.com is the only owner, so their owner rights can't be removed."
  end
end
