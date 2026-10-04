require "application_system_test_case"

# The chip input (`Admin::ChipInputComponent`, `admin--chip-input`) on the post
# editor: tags with autocomplete and "Create tag", related posts with the
# type dot and status, keyboard-only use, and the rule that searching alone
# never saves.
class Admin::ChipInputSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    @post = create_post(title: "Chips")
  end

  def open_editor
    visit admin_post_path(@post)
    await_admin_controllers
  end

  def tag_field = find("#post-tag_names")

  def saved? = has_selector?("#post-save-status", text: /\A(● )?SAVED( TO SITE)? \d{2}:\d{2}\z/, wait: 6)

  test "typing, ArrowDown and Enter picks a suggestion as a chip, and it survives a reload" do
    Tag.create!(name: "rails")
    open_editor

    tag_field.send_keys("ra")
    assert_selector "#post-tag_names-listbox [role=option]", text: "rails"
    tag_field.send_keys(:down, :enter)

    assert_selector "[data-controller~='admin--chip-input'] li", text: "rails"
    assert saved?
    assert_equal [ "rails" ], @post.tags.reload.map(&:name)

    visit admin_post_path(@post)
    assert_selector "li[data-chip-value='rails'] button[aria-label='Remove rails']"
  end

  test "typed text that matches nothing is created as a tag, by Enter or a comma" do
    open_editor

    tag_field.send_keys("Brand New")
    assert_selector "#post-tag_names-listbox [role=option]", text: "Create tag “brand new”"
    tag_field.send_keys(:enter)
    assert_selector "li[data-chip-value='brand new']"

    tag_field.send_keys("second,")
    assert_selector "li[data-chip-value='second']"

    assert saved?
    assert_eventually { @post.tags.reload.map(&:name).sort == [ "brand new", "second" ] }
    assert Tag.exists?(name: "brand new")
  end

  test "a duplicate, whatever its case, is not added twice" do
    open_editor
    tag_field.send_keys("rails", :enter)
    tag_field.send_keys("RAILS", :enter)

    assert_selector "li[data-chip-value]", count: 1
  end

  test "Backspace in the empty field removes the last chip and saves" do
    @post = create_post(title: "Tagged", tags: [ "ruby", "rails" ])
    open_editor

    tag_field.send_keys(:backspace)

    assert_selector "li[data-chip-value]", count: 1
    assert saved?
    assert_equal 1, @post.tags.reload.size
  end

  test "removing the only tag saves an empty list" do
    @post = create_post(title: "Tagged", tags: [ "solo" ])
    open_editor

    find("button[aria-label='Remove solo']").click
    assert_no_selector "li[data-chip-value]"
    assert_eventually { @post.tags.reload.empty? }
  end

  test "a chip's remove button is reachable by keyboard, and focus lands on a neighbour" do
    @post = create_post(title: "Tagged", tags: [ "alpha", "beta", "gamma" ])
    open_editor

    tag_field.send_keys(:left)
    assert_equal "Remove gamma", page.evaluate_script("document.activeElement.getAttribute('aria-label')")
    # Typed at the browser, to whatever has focus: Cuprite's `Node#send_keys` would first move focus itself.
    page.driver.browser.keyboard.type(:left)
    assert_equal "Remove beta", page.evaluate_script("document.activeElement.getAttribute('aria-label')")
    page.driver.browser.keyboard.type(:backspace)

    assert_no_selector "li[data-chip-value='beta']"
    assert_equal "Remove gamma", page.evaluate_script("document.activeElement.getAttribute('aria-label')")
    assert_selector "[role=status]", text: "Removed beta.", visible: :all
    assert_eventually { @post.tags.reload.map(&:name).sort == %w[alpha gamma] }
  end

  test "Escape closes the list and the combobox says so" do
    Tag.create!(name: "rails")
    open_editor
    tag_field.send_keys("ra")
    assert_selector "#post-tag_names[aria-expanded='true']"

    tag_field.send_keys(:escape)
    assert_selector "#post-tag_names[aria-expanded='false']"
    assert_no_selector "#post-tag_names-listbox", visible: :visible
  end

  test "searching alone does not save" do
    Tag.create!(name: "rails")
    open_editor
    before = @post.reload.updated_at

    tag_field.send_keys("ra")
    assert_selector "#post-tag_names-listbox [role=option]"
    sleep 1.6
    assert_no_selector "#post-save-status", text: /SAVED|SAVING/i
    assert_equal before, @post.reload.updated_at
  end

  test "a related post chip shows its type dot and Draft" do
    other = create_post(title: "Satellite", published: false)
    open_editor

    find("#post-related_post_ids").send_keys("Sat")
    assert_selector "#post-related_post_ids-listbox [role=option]", text: "Satellite"
    assert_selector "#post-related_post_ids-listbox [role=option]", text: "Draft"
    find("#post-related_post_ids").send_keys(:down, :enter)

    chip = find("li[data-chip-value='#{other.id}']")
    assert_text chip, "Satellite"
    assert chip.has_text?("· Draft")
    assert chip.has_selector?(".admin-chip__dot:not([hidden])")
    assert saved?
    assert_equal [ other.id ], @post.post_relations.reload.pluck(:related_post_id)
  end

  test "a view-only editor's chip input is inert" do
    @post = create_post(title: "Tagged", tags: [ "alpha" ])
    sign_in_via_form(users(:reader))
    open_editor

    assert_selector "#post-tag_names:disabled"
    assert_selector "button[aria-label='Remove alpha']:disabled"
  end
end
