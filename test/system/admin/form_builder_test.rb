require "application_system_test_case"

# The form builder in a browser: fields added from the picker, moved with
# the up and down icon buttons (found by their names), removed, and saved
# explicitly through the save bar; a choice field's choices added and
# removed; and leaving with unsaved changes asks, as on every save-bar
# screen. Nothing is written until Save. On the forms list, a row's ⋯ menu
# opens whole over the page, lifted out of the table's sideways scroll.
class Admin::FormBuilderSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    root_page
    sign_in_via_form(users(:one))
  end

  def footer = ".admin-save-bar"

  def rows = all("[data-admin--forms--builder-target=row]:not([hidden])")

  def labels = rows.map { |row| row.find("input[name$='[label][en]']").value }

  def open_builder(form)
    visit_screen admin_form_path(form)
    assert_selector footer, text: /No unsaved changes/i
  end

  def add_field(type_label, label)
    within(".admin-block-picker") { press type_label }
    # The new row's Label input takes the focus.
    assert_equal rows.size, page.evaluate_script("[...document.querySelectorAll('[data-admin--forms--builder-target=row]:not([hidden])')].indexOf(document.activeElement.closest('[data-admin--forms--builder-target=row]')) + 1")
    page.driver.browser.keyboard.type(label)
  end

  test "add three fields, move the last to the top, remove one, Save: the order is kept and the keys of the kept fields are unchanged" do
    form = forms(:contact)
    open_builder(form)
    stored = form.fields.to_h { |field| [ field.label_in("en"), field.key ] }

    add_field "Short text", "Company"
    add_field "Email address", "Second address"
    add_field "Long text", "Notes"
    assert_equal [ "Your name", "Email address", "Message", "Company", "Second address", "Notes" ], labels

    # An icon button's tooltip says its name, which follows the label typed.
    assert_equal "Move “Notes” up", find("button[aria-label='Move “Notes” up'] [data-tooltip]", visible: :all).text(:all)

    # Found again for every press: a row moved in the document is a new node to the driver.
    5.times { |moves| find("button[aria-label='Move “Notes” up']").click; assert_equal 5 - moves, labels.index("Notes") + 1 }
    assert_equal [ "Notes", "Your name", "Email address", "Message", "Company", "Second address" ], labels
    assert find("button[aria-label='Move “Notes” up']").disabled?, "at the top, up is disabled"
    assert_equal "Move “Notes” down", page.evaluate_script("document.activeElement.getAttribute('aria-label')"),
      "the focus goes to the other arrow of the row"
    assert_selector "[aria-live=polite]", text: "“Notes” moved to 1 of 6.", visible: :all

    rows[2].find("button[aria-label='Remove “Email address”']").click
    assert_equal [ "Notes", "Your name", "Message", "Company", "Second address" ], labels
    assert_selector "[aria-live=polite]", text: "“Email address” removed. Discard brings it back.", visible: :all

    press "Save changes"
    assert_selector "#toasts", text: I18n.t("admin.forms.update.saved")
    form.reload
    assert_equal [ "Notes", "Your name", "Message", "Company", "Second address" ], form.fields.map { |field| field.label_in("en") }
    assert_equal %w[long_text short_text long_text short_text email], form.fields.map(&:type)
    assert_equal stored["Your name"], form.fields.second.key
    assert_equal stored["Message"], form.fields.third.key
    assert_not_includes form.fields.map(&:key), stored["Email address"]
  end

  test "a choice's choices are added and removed, and Save keeps them" do
    form = forms(:newsletter)
    open_builder(form)
    topic = all("[data-admin--forms--builder-target=row]").find { |row| row["data-key"] == "f_topic002" }

    within(topic) do
      press "+ Add choice"
      page.driver.browser.keyboard.type("Events")
      assert_selector "[data-admin--forms--builder-target=choice]", count: 3
      find("button[aria-label='Remove choice “News”']").click
      find("button[aria-label='Move choice “Events” up']").click
    end
    assert_selector footer, text: /unsaved change/i

    press "Save changes"
    assert_selector "#toasts", text: I18n.t("admin.forms.update.saved")
    field = form.reload.fields.find { |stored| stored.key == "f_topic002" }
    assert_equal [ "Events", "Offers" ], field.choices.map { |choice| choice.label_in("en") }
    assert_equal "c_offr0001", field.choices.last.key, "a kept choice keeps its key"

    # A new choice field starts with two empty choices to fill in.
    add_field "Choice", "Colour"
    new_row = rows.last
    assert_equal 2, new_row.all("[data-admin--forms--builder-target=choice]").size
  end

  test "leaving with unsaved changes asks, as every save-bar screen does" do
    form = forms(:contact)
    open_builder(form)

    rows.first.find("button[aria-label='Move “Your name” down']").click
    assert_selector footer, text: /1 unsaved change/i

    within("nav[aria-label='Modules']") { click_link "Posts" }
    assert_selector "dialog#leave-dialog[open]"
    within("dialog#leave-dialog") { press "Keep editing" }
    assert_current_path admin_form_path(form)
    assert_equal [ "Email address", "Your name", "Message" ], labels
    assert_equal %w[f_name0001 f_mail0001 f_text0001], form.reload.fields.map(&:key), "nothing was written"
  end

  test "a row's ⋯ menu on a list of one form opens whole over the page, and the table box does not scroll" do
    forms(:newsletter).update_columns(trashed_at: Time.current) # version: none (a test's row)
    visit_screen admin_forms_path
    assert_selector ".admin-forms-table tbody tr", count: 1

    find("button[aria-label='Actions for Contact']").click
    item = find("tr##{ActionView::RecordIdentifier.dom_id(forms(:contact))} [role=menu] button", text: "Move to trash…")
    boxes = page.evaluate_script(<<~JS)
      (() => {
        const item = [...document.querySelectorAll(".admin-forms-table [role=menu] button")].find((button) => button.textContent.includes("Move to trash"))
        const scroller = document.querySelector(".admin-table-scroll--x")
        const rect = (box) => { const r = box.getBoundingClientRect(); return { top: r.top, bottom: r.bottom, left: r.left, right: r.right } }
        return { item: rect(item), scroller: rect(scroller), viewport: { width: window.innerWidth, height: window.innerHeight },
          scrollTop: scroller.scrollTop, scrollHeight: scroller.scrollHeight, clientHeight: scroller.clientHeight,
          hit: document.elementFromPoint((rect(item).left + rect(item).right) / 2, (rect(item).top + rect(item).bottom) / 2) === item }
      })()
    JS
    assert item.visible?
    assert boxes["item"]["top"] >= 0 && boxes["item"]["bottom"] <= boxes["viewport"]["height"], "the item is inside the window: #{boxes.inspect}"
    assert boxes["item"]["left"] >= 0 && boxes["item"]["right"] <= boxes["viewport"]["width"], "the item is inside the window: #{boxes.inspect}"
    assert boxes["item"]["bottom"] > boxes["scroller"]["bottom"], "the menu hangs past the table box, over the page: #{boxes.inspect}"
    assert boxes["hit"], "the item is the topmost thing at its own centre: nothing clips or covers it"
    assert_equal 0, boxes["scrollTop"]
    assert boxes["scrollHeight"] <= boxes["clientHeight"], "the open menu does not lengthen the table box's scroll: #{boxes.inspect}"
  end
end
