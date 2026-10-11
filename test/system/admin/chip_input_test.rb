require "application_system_test_case"

# The chip input (`Admin::Ui::ChipInputComponent`, `admin--ui--chip-input`) on the post
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

    assert_selector "[data-controller~='admin--ui--chip-input'] li", text: "rails"
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
    page.execute_script(<<~JS)
      window.__patches = 0
      const original = window.fetch
      window.fetch = (input, init) => { if ((init?.method || "GET").toUpperCase() === "PATCH") window.__patches++; return original(input, init) }
    JS

    tag_field.send_keys("ra")
    assert_selector "#post-tag_names-listbox [role=option]"
    # A `focusout` flushes any queued save, so provoke one and count the PATCH
    # requests the page sent (none), rather than waiting on a clock.
    page.execute_script("document.querySelector('#post-tag_names').dispatchEvent(new FocusEvent('focusout', { bubbles: true }))")
    assert_equal 0, page.evaluate_script("window.__patches")
  end

  test "pasted comma-separated text becomes one chip per part, the remainder stays in the field" do
    open_editor

    page.execute_script(<<~JS)
      const input = document.querySelector("#post-tag_names")
      input.focus()
      input.value = "Ruby, rails, par"
      input.dispatchEvent(new Event("input", { bubbles: true }))
    JS

    assert_selector "li[data-chip-value='ruby']"
    assert_selector "li[data-chip-value='rails']"
    assert_no_selector "li[data-chip-value='ruby, rails']"
    assert_equal "par", tag_field.value
    assert saved?
    assert_equal %w[rails ruby], @post.tags.reload.map(&:name).sort
  end

  test "leaving the field with half-typed text commits it as a chip" do
    open_editor

    tag_field.send_keys("halfway")
    find("h1, [data-field-name='title'] input", match: :first).click

    assert_selector "li[data-chip-value='halfway']"
    assert_selector "[role=status]", text: "Added halfway.", visible: :all
    assert saved?
    assert_equal [ "halfway" ], @post.tags.reload.map(&:name)
  end

  test "a tag longer than the limit is tinted at once and the save names it in the error slot" do
    open_editor

    tag_field.send_keys("x" * 51, :enter)

    assert_selector "li.bg-danger-tint[data-invalid]"
    assert_selector "li[data-invalid] .sr-only[data-chip-invalid-note]", text: "(too long)", visible: :all
    assert_selector "#post-tag_names-errors", text: "longer than 50 characters", wait: 6
    assert_empty @post.tags.reload
  end

  test "an existing over-long tag is not tinted, only a name typed in this session is" do
    Tag.new(name: "l" * 60).save!(validate: false)
    Tag.new(name: "m" * 60).save!(validate: false)
    @post = create_post(title: "Legacy")
    @post.tags << Tag.find_by!(name: "l" * 60)
    open_editor

    assert_selector "li[data-chip-value='#{"l" * 60}']"
    assert_no_selector "li[data-invalid]"

    tag_field.send_keys("m" * 58)
    assert_selector "#post-tag_names-listbox [role=option]", text: "m" * 60
    tag_field.send_keys(:down, :enter)
    assert_selector "li[data-chip-value='#{"m" * 60}']"
    assert_no_selector "li[data-invalid]"
  end

  test "an older answer never overwrites a newer one" do
    open_editor
    page.execute_script(<<~JS)
      window.__pending = {}
      const real = window.fetch
      window.fetch = (input, init) => {
        // Only the tag search is held; the editor's live parts (presence, notes) fetch too and take the real one.
        const url = new URL(input.url || input, location.origin)
        if (!url.searchParams.has("q")) return real(input, init)
        const q = url.searchParams.get("q")
        return new Promise((resolve) => {
          window.__pending[q] = () => resolve(new Response(JSON.stringify([{ value: "answer-" + q, label: "answer-" + q, hint: "1 post" }]), { status: 200 }))
        })
      }
    JS

    tag_field.send_keys("a")
    assert_eventually { page.evaluate_script("Object.keys(window.__pending).includes('a')") }
    tag_field.send_keys("b")
    assert_eventually { page.evaluate_script("Object.keys(window.__pending).includes('ab')") }
    page.execute_script("window.__pending['ab']()")
    assert_selector "#post-tag_names-listbox [role=option]", text: "answer-ab"
    page.execute_script("window.__pending['a']()")
    await_frames # the late answer has been delivered and its handlers run; it must have changed nothing
    assert_selector "#post-tag_names-listbox [role=option]", text: "answer-ab"
    texts = all("#post-tag_names-listbox [role=option]").map { |option| option.text.sub(/\s*1 post\z/, "") }
    assert_equal [ "answer-ab", "Create tag “ab”" ], texts
  end

  test "Escape then a late answer does not reopen the list" do
    open_editor
    page.execute_script(<<~JS)
      window.__release = null
      const real = window.fetch
      // Only the tag search is held; the editor's live parts (presence, notes) fetch too and take the real one.
      window.fetch = (input, init) => !new URL(input.url || input, location.origin).searchParams.has("q") ? real(input, init) : new Promise((resolve) => { window.__release = () => resolve(new Response(JSON.stringify([{ value: "late", label: "late" }]), { status: 200 })) })
    JS
    tag_field.send_keys("l")
    assert_eventually { page.evaluate_script("window.__release !== null") }
    tag_field.send_keys(:escape)
    page.execute_script("window.__release()")
    await_frames # the late answer has been delivered and its handlers run
    assert_selector "#post-tag_names[aria-expanded='false']"
  end

  test "the post itself is not offered as a related post" do
    create_post(title: "Chips sibling")
    open_editor

    find("#post-related_post_ids").send_keys("Chips")
    assert_selector "#post-related_post_ids-listbox [role=option]", text: "Chips sibling"
    assert_no_selector "#post-related_post_ids-listbox [role=option]", text: /\AChips\s*\z/
    assert_equal 1, all("#post-related_post_ids-listbox [role=option]").size
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
