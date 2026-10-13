require "application_system_test_case"

# The Code block's card in the page editor, in a browser (code block spec
# §3): typed into and saved by itself with its white space as typed, refused
# over the limit with the text left in the field, and read-only for a second
# person while the first holds it. And the designer's answers C3 and C4: the
# field's height follows the code between six and twenty-four lines, and the
# counter says its unit, how far over, and is announced twice at most.
class Admin::CodeBlockSystemTest < ApplicationSystemTestCase
  TYPED = "    indented first\n  second".freeze
  # White space a browser could normalise: the first line's indentation, a
  # blank inner line, a tab (which cannot be typed: Tab leaves the field) and
  # trailing spaces on an inner line.
  WHITE = "    indented first  \n\n\tsecond\n  third".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    users(:one).update!(name: "Olga Braun")
    @page = create_page(title: "Docs", published: false)
    sign_in_via_form(users(:one))
  end

  def open_editor
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
    await_notes_live
  end

  def code_id(block) = "block-#{block.id}-code"

  def code_field(block) = find("##{code_id(block)}")

  # Puts `count` characters into the field as a paste would, in one event.
  def paste(block, count) = paste_text(block, "x" * count)

  def paste_text(block, text)
    page.execute_script("const field = document.getElementById(arguments[0]); field.value = arguments[1]; field.dispatchEvent(new Event('input', { bubbles: true }))", code_id(block), text)
  end

  def lines_of(count) = Array.new(count) { |index| "line #{index + 1}" }.join("\n")

  # How many of its own lines the field is high: its box less its padding
  # and border, in its own line height.
  def lines_high(block)
    page.evaluate_script(<<~JS, code_id(block))
      (() => {
        const field = document.getElementById(arguments[0])
        const style = getComputedStyle(field)
        const around = [style.paddingTop, style.paddingBottom, style.borderTopWidth, style.borderBottomWidth].reduce((sum, value) => sum + parseFloat(value), 0)
        return Math.round((field.getBoundingClientRect().height - around) / parseFloat(style.lineHeight) * 100) / 100
      })()
    JS
  end

  def scrolls_down?(block) = page.evaluate_script("(() => { const field = document.getElementById(arguments[0]); return field.scrollHeight > field.clientHeight })()", code_id(block))

  def announced(block) = page.evaluate_script("document.getElementById(arguments[0]).parentElement.querySelector('[aria-live]').textContent", code_id(block))

  def described_by(block) = page.evaluate_script("document.getElementById(arguments[0]).getAttribute('aria-describedby')", code_id(block))

  def code_of(**settings) = @page.content_blocks.create!(block_type: "code", position: @page.content_blocks.count, settings: settings.stringify_keys)

  test "a Code block added from the picker is typed into, saved by itself, and keeps its indentation after a reload; Tab leaves the field" do
    open_editor
    # Scoped to the picker: the rich-text toolbar has a "Code block" button, and a label is matched as a part.
    within("#block-picker-end") { press "Code" }
    assert_selector ".admin-block-card textarea[name='block[settings][code]']"
    block = @page.content_blocks.sole
    await_admin_controllers

    code_field(block).set(TYPED)
    select "Ruby", from: "block-#{block.id}-language"
    assert_writes_settled
    assert_equal({ "language" => "ruby", "code" => TYPED }, block.reload.settings)

    code_field(block).send_keys(:tab)
    assert_not_equal code_id(block), page.evaluate_script("document.activeElement.id"), "Tab moves on, as in every textarea"
    assert_equal TYPED, code_field(block).value, "and puts nothing into the code"

    open_editor
    assert_equal TYPED, code_field(block).value
    assert_equal "ruby", find("#block-#{block.id}-language").value
    assert_selector "##{code_id(block)}-count", visible: :hidden
  end

  test "from 18,000 characters the field counts; over 20,000 the save is refused, the text stays and nothing is stored" do
    block = @page.content_blocks.create!(block_type: "code", position: 0, settings: { "code" => "kept = 1" })
    open_editor
    assert_selector "##{code_id(block)}-count", visible: :hidden

    paste(block, 18_412)
    assert_selector "##{code_id(block)}-count.text-meta", exact_text: "18,412 of 20,000 characters"
    assert_writes_settled
    assert_equal 18_412, block.reload.settings["code"].length

    paste(block, 20_001)
    assert_selector "##{code_id(block)}-errors", text: "Code is too long (maximum is 20,000 characters)"
    assert_selector "##{code_id(block)}-count.text-danger-ink", exact_text: "20,001 of 20,000 characters · 1 over"
    assert_equal 20_001, page.evaluate_script("document.getElementById('#{code_id(block)}').value.length"), "the refused text is still in the field"
    assert_equal 18_412, block.reload.settings["code"].length, "and nothing was written"
  end

  test "while one person types in the code, a second person's card is read-only with the same text" do
    block = @page.content_blocks.create!(block_type: "code", position: 0, settings: { "language" => "ruby", "code" => "as written" })
    open_editor
    code_field(block).set(TYPED)
    assert_writes_settled
    assert_equal TYPED, block.reload.settings["code"]

    using_session(:dana) do
      sign_in_via_form(users(:two))
      open_editor

      assert_selector "#content_block_#{block.id}[data-editing-held=true] [data-editing-kind=held]", text: "Olga Braun is editing this block"
      assert_selector "##{code_id(block)}[readonly]"
      assert_equal TYPED, code_field(block).value
      assert_selector "#block-#{block.id}-language[disabled]"
      assert_no_selector "#content_block_#{block.id} form[data-controller~='admin--saving--autosave']"

      code_field(block).send_keys("ZZZ")
      await_frames
      assert_equal TYPED, code_field(block).value
    end
    assert_equal TYPED, block.reload.settings["code"]
  end

  # Task 5's review, M1: the white space a browser-side change to the field
  # could lose goes through a real browser, a save and a reload, and to a
  # second person's read-only field.
  test "a tab, a blank inner line and trailing spaces survive the browser, the save, a reload and a second person's read-only field" do
    block = code_of(code: "x = 1")
    open_editor

    paste_text(block, WHITE)
    assert_writes_settled
    assert_equal WHITE, block.reload.settings["code"]
    assert_equal WHITE, code_field(block).value

    using_session(:dana) do
      sign_in_via_form(users(:two))
      open_editor
      assert_selector "##{code_id(block)}[readonly]"
      assert_equal WHITE, code_field(block).value
    end

    open_editor
    assert_equal WHITE, code_field(block).value
    assert_equal WHITE, block.reload.settings["code"]
  end

  # Design answer C3. By the stylesheet alone: nothing measures the field.
  test "the field is six lines high for three lines of code, twelve for twelve, and twenty-four for forty, which it then scrolls; and it follows what is typed" do
    three = code_of(code: lines_of(3))
    twelve = code_of(code: lines_of(12))
    forty = code_of(code: lines_of(40))
    empty = code_of
    open_editor

    assert_equal [ 6, 12, 24, 6 ], [ three, twelve, forty, empty ].map { |block| lines_high(block) }
    assert_equal [ false, false, true, false ], [ three, twelve, forty, empty ].map { |block| scrolls_down?(block) }
    assert_equal "14px", page.evaluate_script("getComputedStyle(document.getElementById('#{code_id(three)}')).fontSize")
    assert_equal "2", page.evaluate_script("getComputedStyle(document.getElementById('#{code_id(three)}')).tabSize")

    paste_text(empty, lines_of(13))
    assert_equal 13, lines_high(empty)
    paste_text(empty, lines_of(40))
    assert_equal 24, lines_high(empty)
    assert scrolls_down?(empty)
    paste_text(empty, lines_of(2))
    assert_equal 6, lines_high(empty)
    assert_writes_settled
  end

  test "a line of three hundred characters is not wrapped, scrolls inside the field, and neither the field nor its card grows or scrolls sideways" do
    block = code_of(code: lines_of(3))
    open_editor
    measure = "(() => { const field = document.getElementById('#{code_id(block)}'); const card = field.closest('.admin-block-card'); return [field.getBoundingClientRect().width, card.getBoundingClientRect().width] })()"
    before = page.evaluate_script(measure)

    paste_text(block, "#{lines_of(2)}\nlong = \"#{"a" * 300}\"")

    assert_equal before, page.evaluate_script(measure), "the field's and the card's widths are what they were"
    assert_equal [ "pre", true, true, true ], page.evaluate_script(<<~JS)
      (() => {
        const field = document.getElementById("#{code_id(block)}")
        const card = field.closest(".admin-block-card")
        return [getComputedStyle(field).whiteSpaceCollapse === "preserve" && getComputedStyle(field).textWrapMode === "nowrap" ? "pre" : getComputedStyle(field).whiteSpace,
                field.scrollWidth > field.clientWidth, card.scrollWidth <= card.clientWidth, document.documentElement.scrollWidth <= document.documentElement.clientWidth]
      })()
    JS
    assert_operator lines_high(block), :>=, 6
    assert_operator lines_high(block), :<, 8, "three lines and a scrollbar are still about six lines high"
    assert_writes_settled
  end

  # A block in a section is drawn with the page and hidden until its tile is
  # pressed (Task 5's review, M5): a field sized by measuring would measure
  # nothing there.
  test "a Code block of twelve lines in a section's lane, opened from its tile, has a twelve-line field" do
    section = @page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "two" })
    block = @page.content_blocks.create!(block_type: "code", position: 0, section_id: section.id, section_column: 2, settings: { "code" => lines_of(12) })
    open_editor
    assert_selector "#block-#{block.id}-panel", visible: :hidden

    find("##{ActionView::RecordIdentifier.dom_id(block)} .admin-block-tile__face").click

    assert_selector "#block-#{block.id}-panel ##{code_id(block)}"
    assert_equal 12, lines_high(block)
    paste_text(block, lines_of(30))
    assert_equal 24, lines_high(block)
    assert_writes_settled
  end

  test "a field someone else holds is read-only and as high as the same code is for the person who holds it" do
    block = code_of(code: lines_of(9))
    open_editor
    paste_text(block, lines_of(15))
    assert_writes_settled
    mine = [ lines_high(block), page.evaluate_script("getComputedStyle(document.getElementById('#{code_id(block)}')).whiteSpaceCollapse") ]
    assert_equal 15, mine.first

    using_session(:dana) do
      sign_in_via_form(users(:two))
      open_editor

      assert_selector "##{code_id(block)}[readonly]"
      assert_equal mine, [ lines_high(block), page.evaluate_script("getComputedStyle(document.getElementById('#{code_id(block)}')).whiteSpaceCollapse") ]
    end
  end

  # Design answer C4. `announced` is the polite region beside the counter:
  # written when the counter appears and when the text passes the limit, and
  # at no other keystroke.
  test "the counter is announced once when it appears and once when the text passes the limit, not at each keystroke, and describes the field only while it shows" do
    block = code_of(code: "kept = 1")
    open_editor
    assert_equal [ "", nil ], [ announced(block), described_by(block) ]

    paste(block, 17_999)
    assert_selector "##{code_id(block)}-count", visible: :hidden
    assert_equal [ "", nil ], [ announced(block), described_by(block) ]

    paste(block, 18_000)
    assert_selector "##{code_id(block)}-count", exact_text: "18,000 of 20,000 characters"
    assert_equal [ "18,000 of 20,000 characters", "#{code_id(block)}-count" ], [ announced(block), described_by(block) ]

    code_field(block).send_keys("yz")
    assert_selector "##{code_id(block)}-count", exact_text: "18,002 of 20,000 characters"
    assert_equal "18,000 of 20,000 characters", announced(block), "a keystroke is not announced"

    paste(block, 20_000)
    assert_selector "##{code_id(block)}-count.text-meta", exact_text: "20,000 of 20,000 characters"
    assert_equal "18,000 of 20,000 characters", announced(block), "at the limit is not over it"

    paste(block, 20_412)
    assert_selector "##{code_id(block)}-count.text-danger-ink", exact_text: "20,412 of 20,000 characters · 412 over"
    assert_equal "20,412 of 20,000 characters · 412 over", announced(block)
    paste(block, 20_500)
    assert_selector "##{code_id(block)}-count", exact_text: "20,500 of 20,000 characters · 500 over"
    assert_equal "20,412 of 20,000 characters · 412 over", announced(block), "further over is not announced again"
    assert_selector "##{code_id(block)}-errors", text: "Code is too long (maximum is 20,000 characters)"

    # Down again says nothing and empties the region, so the next time up is said.
    paste(block, 19_000)
    assert_selector "##{code_id(block)}-count.text-meta", exact_text: "19,000 of 20,000 characters"
    assert_equal [ "", "#{code_id(block)}-count" ], [ announced(block), described_by(block) ]
    paste(block, 100)
    assert_selector "##{code_id(block)}-count", visible: :hidden
    assert_equal [ "", nil ], [ announced(block), described_by(block) ]
    assert_writes_settled

    # A paste from below the threshold to over the limit: one announcement, the over-limit one.
    paste(block, 21_000)
    assert_selector "##{code_id(block)}-count", exact_text: "21,000 of 20,000 characters · 1,000 over"
    assert_equal [ "21,000 of 20,000 characters · 1,000 over", "#{code_id(block)}-count" ], [ announced(block), described_by(block) ]
  end

  test "a page that arrives with the counter showing draws what the script draws, announces nothing, and the counter is the field's description" do
    block = code_of(code: "x" * 18_412)
    open_editor

    assert_selector "##{code_id(block)}-count.text-meta", exact_text: "18,412 of 20,000 characters"
    assert_equal [ "", "#{code_id(block)}-count" ], [ announced(block), described_by(block) ]

    # A page shown again from a copy that kept an announcement: the script
    # empties the region when it connects, so the old count is not standing
    # there and the next step up is said.
    page.execute_script(<<~JS, code_id(block))
      const wrapper = document.getElementById(arguments[0]).parentElement
      wrapper.removeAttribute("data-controller")
      Promise.resolve().then(() => { wrapper.querySelector("[aria-live]").textContent = "20,412 of 20,000 characters · 412 over"; wrapper.setAttribute("data-controller", "admin--editor--code-limit") })
    JS
    await_js("window.Stimulus.getControllerForElementAndIdentifier(document.getElementById('#{code_id(block)}').parentElement, 'admin--editor--code-limit') && document.getElementById('#{code_id(block)}').parentElement.querySelector('[aria-live]').textContent === ''")
    paste(block, 20_412)
    assert_selector "##{code_id(block)}-count", exact_text: "20,412 of 20,000 characters · 412 over"
    assert_equal "20,412 of 20,000 characters · 412 over", announced(block)
  end

  # Design answer C6: on a translation tab the code is read-only in its
  # frame, the line above it names the default language as a link, and the
  # link is the header's own language tab: a visit to the default tab, where
  # the code is a field again. The caption stays a field on the tab.
  test "on a translation tab the code is read-only under a line whose language is a link to the default tab, and the caption is still edited there" do
    with_locales(%w[en de], default: "en")
    block = code_of(language: "ruby", filename: "a.rb", code: WHITE)
    visit "/cs-studio/pages/#{@page.id}?locale=de"
    await_admin_controllers
    await_notes_live

    assert_no_selector "##{code_id(block)}"
    find("#content_block_#{block.id} details[data-shared-fields] summary").click
    assert_selector "#content_block_#{block.id} [data-code-note]", exact_text: "Code isn't translated. Edit it on the English tab."
    assert_equal WHITE, page.evaluate_script("document.querySelector('#content_block_#{block.id} details[data-shared-fields] pre').textContent")
    assert_equal "12px", page.evaluate_script("getComputedStyle(document.querySelector('#content_block_#{block.id} [data-code-note]')).fontSize")
    assert_equal find(".admin-language-tabs a", text: "English")[:href], find("#content_block_#{block.id} [data-code-note] a", exact_text: "English")[:href], "the link is the header's own tab"

    fill_in "block-#{block.id}-caption", with: "Ein Beispiel"
    assert_writes_settled
    assert_equal "Ein Beispiel", Mobility.with_locale(:de) { block.reload.caption }
    assert_equal WHITE, block.settings["code"]

    click_frame_link { find("#content_block_#{block.id} [data-code-note] a").click }
    assert_no_current_path(/locale=/)
    await_admin_controllers
    assert_selector "textarea##{code_id(block)}:not([readonly])"
    assert_equal WHITE, code_field(block).value
    assert_selector ".admin-language-tabs [aria-current='true']", exact_text: "English"
  end
end
