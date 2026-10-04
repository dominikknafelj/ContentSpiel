require "application_system_test_case"

# The invalid-field border is derived by CSS from the field's error slot
# (content-spiel.tailwind.css, "Invalid field border"): autosave streams
# replace the slot but never the input, so a server-rendered class would be
# stale after a failed autosave and again after the fix. This proves both
# directions in a real browser.
class Admin::FieldErrorBorderSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    create_page(title: "Taken")
    @page = create_page(title: "About")
  end

  # The computed colour of `--cs-danger`, read through a probe element so the
  # comparison is between two computed `rgb()` strings, whatever colour
  # syntax the token is written in.
  def danger_colour
    page.evaluate_script(<<~JS)
      (() => {
        const probe = document.createElement("div")
        probe.style.cssText = "border: 1px solid; border-color: var(--cs-danger)"
        document.body.appendChild(probe)
        const colour = getComputedStyle(probe).borderTopColor
        probe.remove()
        return colour
      })()
    JS
  end

  def border_colour(selector)
    page.evaluate_script("getComputedStyle(document.querySelector(#{selector.to_json})).borderTopColor")
  end

  test "a field that fails an autosave turns red with its message, and loses it once fixed" do
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
    wrapper = ".admin-prefix-input"
    assert_not_equal danger_colour, border_colour(wrapper)

    fill_in "Slug", with: "taken"
    assert_selector "[id$='slug-errors'] p", text: /taken/i, wait: 10
    assert_equal danger_colour, border_colour(wrapper)

    fill_in "Slug", with: "about-us"
    assert_no_selector "[id$='slug-errors'] p", wait: 10
    assert_not_equal danger_colour, border_colour(wrapper)
  end
end
