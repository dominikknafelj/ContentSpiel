require "application_system_test_case"

# Your account as drawn (Design System v262, A1, A2, A4; the page frame of
# 1794894016-5ccc): one card per form, each form's Save inside its own card
# and below that card's last field, nothing floating or sticky at any width
# or scroll position, the body in Settings' 760px column, and nothing takes
# the focus on load.
class Admin::AccountLayoutSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
  end

  # For each form: its Save's box, its card's box, the bottom of the card's
  # last field, and whether any part of the screen is fixed or sticky.
  def frames
    page.evaluate_script(<<~JS)
      (() => {
        const box = (element) => { const r = element.getBoundingClientRect(); return { top: r.top, bottom: r.bottom, left: r.left, right: r.right, width: r.width } }
        const forms = {}
        for (const id of ["profile-form", "password-form"]) {
          const form = document.getElementById(id)
          const save = document.querySelector(`button[type=submit][form=${id}]`)
          const card = save.closest("section.admin-settings-card")
          const fields = Array.from(card.querySelectorAll("input:not([type=hidden]), select, textarea")).filter((field) => field.form === form)
          forms[id] = { save: box(save), card: card ? box(card) : null, in_own_card: Boolean(card && form.contains(card)), last_field: Math.max(...fields.map((field) => box(field.closest(".admin-column, label") || field).bottom)) }
        }
        const pinned = Array.from(document.querySelectorAll("#content *")).filter((element) => ["fixed", "sticky"].includes(getComputedStyle(element).position)).map((element) => element.outerHTML.slice(0, 80))
        return { forms, pinned, body: box(document.querySelector(".admin-page__body")) }
      })()
    JS
  end

  def assert_footers_inside_their_cards(at)
    drawn = frames
    assert_empty drawn["pinned"], "#{at}: nothing on Your account floats or sticks"
    drawn["forms"].each do |id, form|
      assert form["in_own_card"], "#{at}: #{id}'s Save stands in its own card"
      assert_operator form["save"]["top"], :>=, form["last_field"] - 1, "#{at}: #{id}'s Save is below its card's last field"
      assert_operator form["save"]["bottom"], :<=, form["card"]["bottom"] + 1, "#{at}: #{id}'s Save is inside its card"
    end
    drawn
  end

  test "each form's Save is inside its own card, under its last field, and nothing floats, at a desktop and a phone, scrolled or not" do
    [ [ 1440, 900 ], [ 390, 844 ] ].each do |width, height|
      at_window(width, height: height) do
        visit_screen admin_account_path
        drawn = assert_footers_inside_their_cards("#{width}px at the top")
        assert_operator drawn["body"]["width"], :<=, 761, "the body is Settings' column at most"
        assert_in_delta 760, drawn["body"]["width"], 1 if width == 1440

        page.execute_script("window.scrollTo(0, document.documentElement.scrollHeight / 2)")
        assert_footers_inside_their_cards("#{width}px half way down")
        page.execute_script("window.scrollTo(0, document.documentElement.scrollHeight)")
        assert_footers_inside_their_cards("#{width}px at the end")
      end
    end
  end

  test "nothing takes the focus on load, and a contained footer says nothing until a change" do
    visit_screen admin_account_path

    assert_includes [ "BODY", nil ], page.evaluate_script("document.activeElement && document.activeElement.tagName"), "no field is focused on load"
    assert_no_text "No unsaved changes"
    fill_in "Your name", with: "Ada"
    assert_selector "#profile-form .admin-save-bar", text: "1 unsaved change"
    assert_no_selector "#password-form .admin-save-bar", text: /unsaved/
  end
end
