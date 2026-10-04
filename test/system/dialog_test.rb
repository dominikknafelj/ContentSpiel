require "application_system_test_case"

# The one dialog component and controller (`admin--dialog` on <body>): a
# trigger opens a dialog by id, a destructive one starts on Cancel, Esc
# closes without acting, and the confirm button does the write.
class DialogSystemTest < ApplicationSystemTestCase
  test "a destructive confirm opens on Cancel, Escape backs out, confirming deletes" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    tag = Tag.create!(name: "dialog-tag")
    sign_in_via_form(users(:one))

    visit "/cs-studio/tags"
    await_admin_controllers

    within("##{ActionView::RecordIdentifier.dom_id(tag)}") { press "Delete" }
    assert_selector "dialog[open]"
    assert_equal "Cancel", page.evaluate_script("document.activeElement.textContent.trim()")

    find("dialog[open]").send_keys(:escape)
    assert_no_selector "dialog[open]"
    assert_selector "##{ActionView::RecordIdentifier.dom_id(tag)}"

    within("##{ActionView::RecordIdentifier.dom_id(tag)}") { press "Delete" }
    within("dialog[open]") { press "Delete" }
    assert_no_selector "##{ActionView::RecordIdentifier.dom_id(tag)}"
    assert_not Tag.exists?(tag.id)
  end

  # A drag that starts inside the dialog and is released on the backdrop
  # fires `click` on the <dialog> element (their common ancestor); it must
  # not count as a backdrop click. Cuprite's low-level mouse API expresses
  # it: press inside, release outside the dialog's box.
  test "a press inside the dialog released on the backdrop leaves it open; a plain backdrop click closes it" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    tag = Tag.create!(name: "drag-tag")
    sign_in_via_form(users(:one))
    visit "/cs-studio/tags"
    await_admin_controllers

    within("##{ActionView::RecordIdentifier.dom_id(tag)}") { press "Delete" }
    assert_selector "dialog[open]"

    box = page.evaluate_script("(() => { const r = document.querySelector('dialog[open]').getBoundingClientRect(); return [r.left, r.top, r.right, r.bottom] })()")
    left, top, right, bottom = box
    inside = [ (left + right) / 2, top + 20 ]
    outside = [ 5, 5 ]
    page.driver.browser.mouse.move(x: inside[0], y: inside[1])
    page.driver.browser.mouse.down
    page.driver.browser.mouse.move(x: outside[0], y: outside[1])
    page.driver.browser.mouse.up
    sleep 0.3
    assert_selector "dialog[open]"

    page.driver.browser.mouse.click(x: outside[0], y: outside[1])
    assert_no_selector "dialog[open]"
  end

  # Round 1 departure: Design read the backdrop as ~50% grey; it must be ink at
  # 38%. The probe is an element painted with the same expression, so this
  # compares what the browser resolves for the real ::backdrop and scrim in
  # whichever theme is active (ink is dark in light and light in dark).
  test "the dialog backdrop and the drawer scrim are ink at 38%" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    tag = Tag.create!(name: "overlay-tag")
    sign_in_via_form(users(:one))
    visit "/cs-studio/tags"
    await_admin_controllers

    probe = <<~JS
      (() => {
        const p = document.createElement("div")
        p.style.background = "color-mix(in oklab, var(--cs-ink) 38%, transparent)"
        document.body.appendChild(p)
        const value = getComputedStyle(p).backgroundColor
        p.remove()
        return value
      })()
    JS
    expected = page.evaluate_script(probe)
    assert_match(/\A(rgba?|color|oklab)\(/, expected)

    within("##{ActionView::RecordIdentifier.dom_id(tag)}") { press "Delete" }
    assert_selector "dialog[open]"
    assert_equal expected, page.evaluate_script('getComputedStyle(document.querySelector("dialog[open]"), "::backdrop").backgroundColor')
    # Not the old ~50%: the alpha is the 38% (0.38) the expression asks for.
    alpha = expected[%r{/\s*([\d.]+)\s*\)}, 1] || expected[/,\s*([\d.]+)\)\z/, 1]
    assert_in_delta 0.38, alpha.to_f, 0.01
  end
end
