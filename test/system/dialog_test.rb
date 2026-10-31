require "application_system_test_case"

# The one dialog component and controller (`admin--ui--dialog` on <body>): a
# trigger opens a dialog by id, a destructive one starts on Cancel, Esc
# closes without acting, and the confirm button does the write.
class DialogSystemTest < ApplicationSystemTestCase
  # The Tags list's row menu (round 3): "Delete tag…" opens the list's one Delete dialog.
  def open_delete_tag_dialog(tag)
    row = "##{ActionView::RecordIdentifier.dom_id(tag)}"
    find("#{row} button[aria-label^='Actions for']").click
    find("#{row} [role=menu] button", text: "Delete tag…").click
  end

  test "a destructive confirm opens on Cancel, Escape backs out, confirming deletes" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    tag = Tag.create!(name: "dialog-tag")
    sign_in_via_form(users(:one))

    visit "/cs-studio/tags"
    await_admin_controllers

    open_delete_tag_dialog(tag)
    assert_selector "dialog[open]"
    assert_equal "Cancel", page.evaluate_script("document.activeElement.textContent.trim()")

    find("dialog[open]").send_keys(:escape)
    assert_no_selector "dialog[open]"
    assert_selector "##{ActionView::RecordIdentifier.dom_id(tag)}"

    open_delete_tag_dialog(tag)
    within("dialog[open]") { press "Delete tag" }
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

    open_delete_tag_dialog(tag)
    assert_selector "dialog[open]"

    box = page.evaluate_script("(() => { const r = document.querySelector('dialog[open]').getBoundingClientRect(); return [r.left, r.top, r.right, r.bottom] })()")
    left, top, right, bottom = box
    inside = [ (left + right) / 2, top + 20 ]
    outside = [ 5, 5 ]
    page.driver.browser.mouse.move(x: inside[0], y: inside[1])
    page.driver.browser.mouse.down
    page.driver.browser.mouse.move(x: outside[0], y: outside[1])
    page.driver.browser.mouse.up
    await_frames # the backdrop's click handler has run by now: the dialog is open because it was left alone
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

    open_delete_tag_dialog(tag)
    assert_selector "dialog[open]"
    assert_equal expected, page.evaluate_script('getComputedStyle(document.querySelector("dialog[open]"), "::backdrop").backgroundColor')
    # Not the old ~50%: the alpha is the 38% (0.38) the expression asks for.
    alpha = expected[%r{/\s*([\d.]+)\s*\)}, 1] || expected[/,\s*([\d.]+)\)\z/, 1]
    assert_in_delta 0.38, alpha.to_f, 0.01
  end

  # Review B, M2 (final fix wave 1): a dialog opened from a MENU item. The
  # menu closes as the item is picked, so the element the browser would hand
  # focus back to when the dialog closes is hidden, and focus fell to <body>:
  # a keyboard user was back at the top of the page. It goes to the menu's
  # own button instead.
  test "cancelling a dialog opened from a menu item returns focus to the menu's button" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    page_record = create_page(title: "About")
    block = page_record.content_blocks.create!(block_type: :image, position: 0)
    visit "/cs-studio/pages/#{page_record.id}"
    await_admin_controllers

    # A block card's menu.
    within("[data-block-id='#{block.id}']") do
      find("button[aria-label='Block actions']").click
      find("button", text: "Delete block…").click
    end
    assert_selector "dialog[open]", text: "Delete this block?"
    within("dialog[open]") { click_button "Cancel" }
    assert_no_selector "dialog[open]"
    # (Polled: the dialog's `close` event follows its closing by a task.)
    assert_selector "[data-block-id='#{block.id}'] button[aria-label='Block actions']:focus"

    # The editor header's menu; Escape closes like Cancel.
    open_editor_menu
    find("header.admin-editor-header [role=menu] button", text: "Unpublish…").click
    assert_selector "dialog[open]", text: "Unpublish this page?"
    find("dialog[open]").send_keys(:escape)
    assert_no_selector "dialog[open]"
    assert_selector "header.admin-editor-header button[aria-label='More actions']:focus"
  end
end
