require "test_helper"

class Admin::UsersScreen::SessionsZoneComponentTest < ViewComponent::TestCase
  def zone(user, count:, own: false)
    with_request_url("/cs-studio/users/#{user.id}/edit") do
      render_inline Admin::UsersScreen::SessionsZoneComponent.new(user: user, own: own, count: count)
    end
  end

  test "the body counts the open sessions and the trigger opens a dialog with the primary confirm" do
    user = users(:two)
    zone(user, count: 2)

    assert_selector "section.admin-action-zone.mt-6[data-zone=sessions][aria-labelledby=sessions-zone-title][data-controller='admin--saving--pending-lock']"
    assert_selector "h2#sessions-zone-title.text-h3", text: "Sessions"
    assert_text "two@example.com has 2 open sessions. Ending them signs two@example.com out everywhere."
    assert_selector "button[data-action='admin--ui--dialog#open'][data-admin--ui--dialog-id-param='sessions-user-#{user.id}'][data-admin--saving--pending-lock-target=control]:not([disabled])", text: "End all sessions…"
    assert_selector "dialog#sessions-user-#{user.id}", visible: :all do
      assert_selector "dialog", text: "End all of two@example.com's sessions?", visible: :all
      assert_selector "dialog", text: "two@example.com is signed out on every browser and must sign in again.", visible: :all
      assert_selector "form[action='/cs-studio/users/#{user.id}/sessions'] input[name=_method][value=delete]", visible: :all
      assert_selector "button.bg-accent[type=submit]", text: "End all sessions", visible: :all
    end
    assert_no_selector "dialog button.bg-danger", visible: :all
  end

  test "one session is said in the singular" do
    zone(users(:two), count: 1)

    assert_text "two@example.com has 1 open session. Ending it signs two@example.com out everywhere."
  end

  test "with no session the trigger is disabled with its reason and there is no dialog" do
    zone(users(:two), count: 0)

    assert_text "Ending sessions signs a person out everywhere."
    assert_text "two@example.com has no open sessions."
    assert_selector "button[disabled]", text: "End all sessions…"
    assert_no_selector "dialog", visible: :all
  end

  test "on your own account it is drawn disabled and points to Your account" do
    zone(users(:one), count: 3, own: true)

    assert_text "End your own sessions from Your account."
    assert_selector "button[disabled]", text: "End all sessions…"
    assert_no_selector "dialog", visible: :all
  end
end
