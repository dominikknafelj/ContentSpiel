require "application_system_test_case"

# The keyboard of CS Studio's shared controls and dialogs, each a test its
# component's contract names (`keyboard:`, `docs/reference/design-system.md`,
# "Component contract"): a control is reached with Tab and does with its keys
# what its contract says. A test sets where Tab starts by clicking words
# beside the control (a label's text, a status line), as a person reading the
# screen would, and never focuses the control by script.
class Admin::KeyboardControlsSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
  end

  test "a button is one Tab stop that Enter and Space both press: an image block's Choose image opens the picker" do
    page_record = create_page(title: "Gallery")
    block = page_record.content_blocks.create!(block_type: :image, position: 0)
    visit_editor(page_record)

    card = "[data-block-id='#{block.id}']"
    find("#{card} [data-admin--media--field-target=title]", text: "No image chosen").click
    page.send_keys(:tab)
    assert_equal "Choose image", focused_text

    page.send_keys(:enter)
    assert_selector "dialog#media-picker[open]"
    find("dialog[open]").send_keys(:escape)
    assert_no_selector "dialog[open]"
    assert_selector "#{card} button:focus", text: "Choose image"

    page.send_keys(:space)
    assert_selector "dialog#media-picker[open]"
    find("dialog[open]").send_keys(:escape)
    assert_selector "#{card} button:focus", text: "Choose image"
  end

  test "a dialog starts on its first field, its Close is a Tab stop inside it, and Escape or Close gives the focus back to its trigger" do
    visit_screen admin_forms_path

    find("a", text: "New form", match: :first).click
    assert_selector "dialog#new-form-dialog[open]"
    assert_equal "new_form_name", page.evaluate_script("document.activeElement.id")

    # Back from the first field is the header's Close, still inside the dialog.
    page.send_keys([ :shift, :tab ])
    assert_equal "Close", page.evaluate_script("document.activeElement.getAttribute('aria-label')")
    assert page.evaluate_script("document.activeElement.closest('dialog#new-form-dialog') !== null"), "the focus left the open dialog"
    page.send_keys(:enter)
    assert_no_selector "dialog[open]"
    assert_match(/New form\z/, focused_text)

    page.send_keys(:enter)
    assert_selector "dialog#new-form-dialog[open]"
    find("dialog[open]").send_keys(:escape)
    assert_no_selector "dialog[open]"
    assert_match(/New form\z/, focused_text)
  end

  test "a destructive confirm starts on Cancel, Enter there backs out, and Tab then Enter on the confirm deletes" do
    tag = Tag.create!(name: "keyboard-tag")
    visit_screen admin_tags_path

    open_delete = lambda do
      find("##{ActionView::RecordIdentifier.dom_id(tag)} a[data-tag-details]").click
      find("#tag-detail-#{tag.id} button", text: "Delete tag…").click
      assert_selector "dialog#delete-tag-dialog[open]"
    end

    open_delete.call
    assert_equal "Cancel", focused_text
    page.send_keys(:enter)
    assert_no_selector "dialog[open]"
    assert Tag.exists?(tag.id)

    open_delete.call
    assert_equal "Cancel", focused_text
    page.send_keys(:tab)
    assert_equal "Delete tag", focused_text
    page.send_keys(:enter)
    assert_no_selector "##{ActionView::RecordIdentifier.dom_id(tag)}"
    assert_not Tag.exists?(tag.id)
  end

  # What the action slot holds is the caller's: on the Pages screen it is
  # "+ New page", a link that opens the New page dialog.
  test "an empty state's action is the Tab stop after its words, and Enter on it does what the action does" do
    visit_screen admin_pages_path

    find(".admin-empty-state [data-empty-state-title]", text: "Choose a page from the tree.").click
    page.send_keys(:tab)
    assert_equal "+ New page", focused_text
    page.send_keys(:enter)
    assert_selector "dialog#new-page-dialog[open]"
  end

  test "a checkbox is a Tab stop that Space checks and unchecks: a posts row's Select" do
    post = Current.set(actor: users(:one)) { create_post(title: "Checked by keyboard") }
    visit_screen admin_posts_path

    box = "#select-post-#{post.id}"
    find("thead th", text: "Title").click
    stop_on(box)
    page.send_keys(:space)
    assert find(box, visible: :all).checked?
    page.send_keys(:space)
    assert_not find(box, visible: :all).checked?
    assert_equal "select-post-#{post.id}", page.evaluate_script("document.activeElement.id")
  end

  test "a block's field: its label names its input, and Tab goes from one field's input to the next's" do
    page_record = create_page(title: "Guide")
    block = page_record.content_blocks.create!(block_type: "card", position: 0)
    visit_editor(page_record)

    within("[data-block-id='#{block.id}']") do
      find("label[for='block-#{block.id}-title']").click
      assert_equal "block-#{block.id}-title", page.evaluate_script("document.activeElement.id")
      assert_equal "Title", page.evaluate_script("document.activeElement.labels[0].textContent.trim()")
      page.send_keys("By keyboard")
      page.send_keys(:tab)
      assert_equal "block-#{block.id}-text", page.evaluate_script("document.activeElement.id")
    end
    assert_writes_settled
    assert_equal "By keyboard", block.reload.settings_object(locale: "en").title
  end

  test "a prefixed input: the prefix takes no focus, and Tab from it lands in the input" do
    post = Current.set(actor: users(:one)) { create_post(title: "Prefixed") }
    visit_editor(post)

    input = find_field("Slug")
    prefix = input.find(:xpath, "preceding-sibling::span")
    assert_equal(-1, prefix.evaluate_script("this.tabIndex"))
    prefix.click
    page.send_keys(:tab)
    assert_equal input[:id], page.evaluate_script("document.activeElement.id")
  end

  test "a password field's Show is the Tab stop after its input: Enter shows the password, Space hides it, and the focus stays" do
    visit_screen admin_account_path

    fill_in "New password", with: "a much Longer passw0rd"
    page.send_keys(:tab)
    field = find_field("New password").ancestor(".admin-password-field")
    assert_equal "Show", focused_text

    page.send_keys(:enter)
    assert_equal "text", find_field("New password")[:type]
    assert field.has_css?("button:focus", text: "Hide")

    page.send_keys(:space)
    assert_equal "password", find_field("New password")[:type]
    assert field.has_css?("button:focus", text: "Show")
  end

  # The input stands first in the zone, before its words: Shift+Tab from
  # the words is the stop before them.
  test "a file drop's input is a Tab stop, and its Choose file rings while the keyboard is on it" do
    visit_screen admin_settings_path

    zone = find(".admin-file-drop", match: :first)
    zone.find("p", text: "Drop an image here or").click
    page.send_keys([ :shift, :tab ])
    assert_equal "file", page.evaluate_script("document.activeElement.type")
    assert zone.evaluate_script("this.contains(document.activeElement)"), "Tab did not reach the zone's file input"
    choose = zone.find("label", text: "Choose file")
    assert_equal "solid", choose.evaluate_script("getComputedStyle(this).outlineStyle")

    page.send_keys(:tab)
    assert_equal "none", choose.evaluate_script("getComputedStyle(this).outlineStyle")
  end

  test "a save bar's Save is reached with Tab from the form's fields, and Enter on it saves" do
    visit_screen admin_account_path

    within("#profile-form") do
      fill_in "name", with: "Saved by keyboard"
      stop_on(".admin-save-bar button[type=submit]")
      assert_equal "Save changes", focused_text
      page.send_keys(:enter)
    end
    assert_eventually(message: "the name was never saved") { users(:one).reload.name == "Saved by keyboard" }
    assert_selector "#profile-form .admin-save-bar", text: /No unsaved changes/i
  end

  test "an error summary takes the focus when it is drawn, Tab reaches its link, and Enter there moves the focus to the field" do
    visit_screen new_admin_user_path

    fill_in "Email address", with: users(:two).email_address
    fill_in "Password", with: "a much Longer passw0rd"
    fill_in "Confirm password", with: "a much Longer passw0rd"
    press "Create user"
    assert_selector ".admin-error-summary a[href='#user_email_address']", wait: 10
    assert_eventually(message: "the summary never took the focus") { page.evaluate_script("document.activeElement.classList.contains('admin-error-summary')") }

    page.send_keys(:tab)
    assert_equal "#user_email_address", page.evaluate_script("document.activeElement.getAttribute('href')")
    page.send_keys(:enter)
    assert_eventually(message: "focus never reached the field") { page.evaluate_script("document.activeElement.id") == "user_email_address" }
  end

  private

  def focused_text = page.evaluate_script("document.activeElement.textContent.trim()")

  # Tab until `selector` holds the focus, from wherever Tab starts now, and
  # fail if it is not reached within `limit` stops.
  def stop_on(selector, limit: 30)
    limit.times do
      page.send_keys(:tab)
      return if page.evaluate_script("document.activeElement.matches(#{selector.to_json})")
    end
    flunk "Tab never reached #{selector}"
  end
end
