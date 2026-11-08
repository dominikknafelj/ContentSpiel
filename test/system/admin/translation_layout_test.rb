require "application_system_test_case"

# Side-by-side translation (design pass round 2, Task 7; handoff §4.1, §9 A7):
# in a translation tab a translated field and the primary-language original sit
# beside each other while the form is at least 824px wide, and stack -- the
# original first -- below that. The breakpoint is a CONTAINER query on the
# form, so this is a real-browser test: only layout can show it.
class Admin::TranslationLayoutSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    with_locales(%w[en de], default: "en")
    sign_in_via_form(users(:one))
    @post = create_post(title: "Notes")
    @post.assign_body(rich_doc("Hello **there**"), locale: :en)
    @post.save!
  end

  test "wide, the title field and its original sit side by side" do
    page.current_window.resize_to(1400, 1000)
    visit "/cs-studio/posts/#{@post.id}?locale=de"
    await_admin_controllers

    tops = tops_of("[data-field-name='title'] .admin-translation-pair > div:first-child", "[data-original-for='title']")
    assert_in_delta tops[0], tops[1], 4, "the field and its original should share a row at 1400px (#{tops})"
    assert_operator widths_of("[data-original-for='title']").first, :>, 200
  ensure
    page.current_window.resize_to(1400, 1400)
  end

  # The page editor sits beside the page tree, so at 1100px a block card's form
  # is under 824px wide although the window is not.
  test "narrow, the original stacks above the field and the toolbar is one row" do
    page.current_window.resize_to(1100, 1000)
    page_record = create_page(title: "About")
    block = ContentBlocks::Save.call(ContentBlock.new(owner: page_record), attributes: { block_type: "rich_text" },
      translations: { "en" => { body: rich_doc("Hello **there**") } }).record
    visit "/cs-studio/pages/#{page_record.id}?locale=de"
    await_admin_controllers
    assert_selector "[data-block-id='#{block.id}'] .ProseMirror"

    form_width = page.evaluate_script(%(document.querySelector("[data-block-id='#{block.id}'] form.admin-translation-form").clientWidth))
    assert_operator form_width, :<, 824, "the premise: at 1100px the block form is under 824px (was #{form_width})"

    top_of_original, top_of_field = tops_of("[data-block-id='#{block.id}'] [data-original-for='body']", "[data-block-id='#{block.id}'] .admin-rich-text")
    assert_operator top_of_original, :<, top_of_field - 4, "the original should sit above the field when stacked"

    rows = page.evaluate_script(%[(() => { const t = document.querySelector("[data-block-id='#{block.id}'] [role=toolbar]"); return new Set(Array.from(t.children).map(c => Math.round(c.getBoundingClientRect().top))).size })()])
    assert_equal 1, rows, "the rich-text toolbar should be one row once the original is stacked above it"
  ensure
    page.current_window.resize_to(1400, 1400)
  end

  test "the stacked original folds away" do
    page.current_window.resize_to(1100, 1000)
    page_record = create_page(title: "About")
    visit "/cs-studio/pages/#{page_record.id}?locale=de"
    await_admin_controllers
    page_record.reload

    assert_selector "[data-original-for='title'] details[open]"
    find("[data-original-for='title'] summary").click
    assert_no_selector "[data-original-for='title'] details[open]"
  ensure
    page.current_window.resize_to(1400, 1400)
  end

  # A card folded while stacked must not stay folded (and unreachable, its
  # summary inert) once the column is wide enough for the pair.
  test "a card folded while stacked shows its original again when the window widens" do
    page.current_window.resize_to(1100, 1000)
    page_record = create_page(title: "About")
    visit "/cs-studio/pages/#{page_record.id}?locale=de"
    await_admin_controllers

    find("[data-original-for='title'] summary").click
    assert_no_selector "[data-original-for='title'] details[open]"
    assert_no_selector "[data-original-for='title'] p", text: "About"

    page.current_window.resize_to(1700, 1000)
    # Geometry, not Capybara visibility: Cuprite treats anything inside a
    # closed `<details>` as hidden, which is the state under test.
    height = page.evaluate_script("document.querySelector(\"[data-original-for='title'] p\").getBoundingClientRect().height")
    assert_operator height, :>, 0, "the original should show again once the pair is side by side, whatever the open state"
    tops = tops_of("[data-field-name='title'] .admin-translation-pair > div:first-child", "[data-original-for='title']")
    assert_in_delta tops[0], tops[1], 4
  ensure
    page.current_window.resize_to(1400, 1400)
  end

  # Docked (the tree folded, so the editor area is the content's width), the
  # pair keeps its own threshold, 824px of the block form: at 1200px of
  # editor the blocks column is 812px and the pair stacks; at 1600px the
  # form is past 824px and the halves share it, wider than the 560px they
  # keep undocked.
  test "docked, a block's pair sits side by side once its form is 824px wide" do
    page_record = create_page(title: "About")
    block = ContentBlocks::Save.call(ContentBlock.new(owner: page_record), attributes: { block_type: "rich_text" },
      translations: { "en" => { body: rich_doc("Hello **there**") } }).record
    visit "/cs-studio/pages/#{page_record.id}"
    await_admin_controllers
    page.execute_script("window.localStorage.setItem('cs-tree-folded', '1')")
    form = "[data-block-id='#{block.id}'] form.admin-translation-form"
    original = "[data-block-id='#{block.id}'] [data-original-for='body']"
    field = "[data-block-id='#{block.id}'] .admin-translation-pair > div:first-child"

    page.driver.resize(content_window(1200), 1000)
    visit "/cs-studio/pages/#{page_record.id}?locale=de"
    await_admin_controllers
    assert_selector "[data-block-id='#{block.id}'] .ProseMirror"
    assert_eventually(message: "the premise: the rail docks at 1200px of editor") { docked? }
    assert_operator widths_of(form).first, :<, 824, "the premise: at 1200px the block form is under 824px"
    top_of_original, top_of_field = tops_of(original, field)
    assert_operator top_of_original, :<, top_of_field - 4, "stacked, the original stands above the field"

    page.driver.resize(content_window(1600), 1000)
    visit "/cs-studio/pages/#{page_record.id}?locale=de"
    await_admin_controllers
    assert_selector "[data-block-id='#{block.id}'] .ProseMirror"
    assert_eventually(message: "the rail docks") { docked? }
    assert_operator widths_of(form).first, :>=, 824
    tops = tops_of(field, original)
    assert_in_delta tops[0], tops[1], 4, "side by side, the field and its original share a row"
    field_box, original_box = boxes_of(field, original)
    assert_operator field_box[2], :<, original_box[0], "the field on the left, the original on the right"
    assert_operator field_box[2] - field_box[0], :>, 561, "the halves are not capped at 560px"
    assert_in_delta field_box[2] - field_box[0], original_box[2] - original_box[0], 1, "the two halves share the form"
  ensure
    page.execute_script("try { window.localStorage.removeItem('cs-tree-folded') } catch (error) {}")
    page.driver.resize(1400, 1400)
  end

  private

  def docked? = page.evaluate_script("document.getElementById('editor-grid').hasAttribute('data-rail-docked')")

  # The window whose editor area is `content` wide with the tree folded: the
  # sidebar (240), the strip (44), `<main>`'s padding (48) and the scrollbar.
  def content_window(content) = content + 240 + 44 + 48 + page.evaluate_script("Math.round(window.innerWidth - document.documentElement.getBoundingClientRect().width)")

  def boxes_of(*selectors)
    selectors.map { |selector| page.evaluate_script("(() => { const box = document.querySelector(#{selector.to_json}).getBoundingClientRect(); return [ box.left, box.top, box.right, box.bottom ] })()") }
  end

  def tops_of(*selectors)
    selectors.map { |selector| page.evaluate_script("document.querySelector(#{selector.to_json}).getBoundingClientRect().top").to_f }
  end

  def widths_of(*selectors)
    selectors.map { |selector| page.evaluate_script("document.querySelector(#{selector.to_json}).getBoundingClientRect().width").to_f }
  end
end
