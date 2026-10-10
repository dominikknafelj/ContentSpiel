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

  # The rule under test is CSS, so these inject the nested-wrapper shapes a
  # group field and a repeater render (a Ui::FieldComponent inside a
  # Ui::FieldComponent) straight into the page rather than provoking a sub-field
  # error through a content type's UI.
  def inject_nested_fields
    page.execute_script(<<~JS)
      const form = document.querySelector("form")
      const holder = document.createElement("div")
      holder.id = "nested-probe"
      holder.innerHTML = `
        <div class="admin-field" id="outer">
          <fieldset>
            <div class="admin-field" id="row-a"><input id="a-input" type="text"><div id="a-errors"></div></div>
            <div class="admin-field" id="row-b"><input id="b-input" type="text"><div id="b-errors"></div></div>
          </fieldset>
          <div id="outer-errors"></div>
        </div>
        <div class="admin-column" id="col"><div class="admin-rich-text-popover"><input id="popover-input" type="text"></div><div id="col-errors"></div></div>`
      form.appendChild(holder)
    JS
  end

  def slot_message(id, text = "is invalid")
    page.execute_script("document.getElementById(#{id.to_json}).innerHTML = '<p>#{text}</p>'")
  end

  test "an error in one sub-field colours only that sub-field, not its sibling or the outer wrapper's other inputs" do
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
    inject_nested_fields
    danger = danger_colour
    assert_not_equal danger, border_colour("#a-input")

    slot_message("a-errors")
    assert_equal danger, border_colour("#a-input")
    assert_not_equal danger, border_colour("#b-input")

    slot_message("a-errors", "")
    page.execute_script("document.getElementById('a-errors').innerHTML = ''")
    assert_not_equal danger, border_colour("#a-input")
  end

  test "an error on the outer wrapper itself is a message only: nothing in its nested sub-fields turns red" do
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
    inject_nested_fields
    slot_message("outer-errors")

    assert_not_equal danger_colour, border_colour("#a-input")
    assert_not_equal danger_colour, border_colour("#b-input")
  end

  test "an invalid column does not redden the inputs of a rich-text popover inside it" do
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
    inject_nested_fields
    slot_message("col-errors")

    assert_not_equal danger_colour, border_colour("#popover-input")
  end
end
