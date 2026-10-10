require "application_system_test_case"

# After the password form is saved or refused (the notes handoff's decision
# 42): the page is at `/account#password`, the Password card is in view, and
# the focus is on the message, which a screen reader then announces.
#
# In a window short enough that the card is NOT in view from the top of the
# page, which is where a page drawn again starts: at the suite's own size
# everything on the screen fits, and "in view" would be true of any answer.
class Admin::AccountPasswordAnswerSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    @original = page.current_window.size
    page.current_window.resize_to(1100, 520)
  end

  teardown { page.current_window.resize_to(*@original) }

  def address = page.evaluate_script("window.location.pathname + window.location.hash")

  # How much of the Password card's heading is inside the window.
  def card_in_view?
    page.evaluate_script("(() => { const box = document.querySelector('#password h3').getBoundingClientRect(); return box.top >= 0 && box.bottom <= window.innerHeight })()")
  end

  def send_password(current:, new: "a-new-long-password-1")
    visit admin_account_path
    await_admin_controllers
    assert_equal "/cs-studio/account", address
    fill_in "Current password", with: current
    fill_in "New password", with: new
    fill_in "Confirm new password", with: new
    within("#password") { press "Change password" }
  end

  test "a saved password comes back at #password, with the card in view and the focus on the message" do
    send_password(current: "password")

    assert_selector "#toasts .admin-toast", text: "Password changed. Your other sessions were signed out."
    assert_eventually(message: "the address is #{address}") { address == "/cs-studio/account#password" }
    assert_eventually(message: "the Password card is not in view") { card_in_view? }
    assert_eventually(message: "the focus is not on the message") { page.evaluate_script("document.activeElement.matches('#toasts .admin-toast')") }
    assert users(:one).reload.authenticate("a-new-long-password-1")
  end

  test "a refused password comes back at #password, with the card in view and the focus on the message" do
    send_password(current: "not-my-password")

    assert_selector ".admin-error-summary[role=alert]"
    assert_eventually(message: "the address is #{address}") { address == "/cs-studio/account#password" }
    assert_eventually(message: "the Password card is not in view") { card_in_view? }
    assert_eventually(message: "the focus is not on the message") { page.evaluate_script("document.activeElement.matches('.admin-error-summary')") }
    assert users(:one).reload.authenticate("password")
  end

  # Smooth where motion is welcome, a jump where it is not.
  test "with reduced motion the page jumps to the card: nothing asks for a smooth scroll" do
    page.driver.browser.page.command("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    visit admin_account_path
    await_admin_controllers
    page.execute_script(<<~JS)
      window.__smooth = 0
      const scroll = Element.prototype.scrollIntoView
      Element.prototype.scrollIntoView = function (options) { if (options?.behavior === "smooth") window.__smooth += 1; return scroll.call(this, options) }
    JS
    fill_in "Current password", with: "not-my-password"
    fill_in "New password", with: "a-new-long-password-1"
    fill_in "Confirm new password", with: "a-new-long-password-1"
    within("#password") { press "Change password" }

    assert_selector ".admin-error-summary[role=alert]"
    assert_eventually(message: "the Password card is not in view") { card_in_view? }
    assert_equal 0, page.evaluate_script("window.__smooth")
    assert_equal "auto", page.evaluate_script("getComputedStyle(document.documentElement).scrollBehavior")
  ensure
    page.driver.browser.page.command("Emulation.setEmulatedMedia", features: [])
  end

  # The other form on the page is not the Password card's: its answer stays
  # where it was.
  test "saving the name leaves the address without the fragment" do
    visit admin_account_path
    await_admin_controllers
    fill_in "Your name", with: "Ada"
    within("#profile-form") { press "Save" }

    assert_selector "#toasts .admin-toast", text: "Settings saved"
    assert_equal "/cs-studio/account", address
  end
end
