require "application_system_test_case"

# The editors' form column (layout points spec, A): 760px whatever the window,
# left-aligned in the content column, the header still full width; a
# translation tab two columns of up to 560px (O3). Only layout can show it.
class Admin::FormWidthSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    with_locales(%w[en de], default: "en")
    sign_in_via_form(users(:one))
    @post = create_post(title: "Notes")
    @page = create_page(title: "About")
    ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" },
      translations: { "en" => { body: rich_doc("Hello **there**") } })
  end

  test "at 1600px the post form is 760px wide, starts at the content's left edge, and the header keeps its width" do
    at_1600 do
      visit "/cs-studio/posts/#{@post.id}"
      await_admin_controllers

      form = box("#post-form")
      assert_in_delta 760, form[2] - form[0], 1
      assert_in_delta content_left, form[0], 1
      assert_operator box(".admin-editor-header")[2], :>, 1500
    end
  end

  test "at 1600px the page settings and the block list are 760px wide, one above the other" do
    at_1600 do
      visit "/cs-studio/pages/#{@page.id}"
      await_admin_controllers

      settings = box("#page-settings")
      blocks = box(".admin-content-blocks")
      assert_in_delta 760, settings[2] - settings[0], 1
      assert_in_delta 760, blocks[2] - blocks[0], 1
      assert_in_delta settings[0], blocks[0], 1
    end
  end

  test "at 1600px a translation tab is wider than 760px and at most 1144px, and its pairs sit side by side" do
    at_1600 do
      visit "/cs-studio/posts/#{@post.id}?locale=de"
      await_admin_controllers

      form = box("#post-form")
      assert_operator form[2] - form[0], :>, 760
      assert_operator form[2] - form[0], :<=, 1144
      field = box("[data-field-name='title'] .admin-translation-pair > div:first-child")
      original = box("[data-original-for='title']")
      assert_in_delta field[1], original[1], 4, "the field and its original share a row"
      assert_operator original[2] - original[0], :<=, 561
    end
  end

  private

  def at_1600
    page.driver.resize(1600, 1000)
    yield
  ensure
    page.driver.resize(1400, 1400)
  end

  def box(selector)
    page.evaluate_script("(() => { const box = document.querySelector(#{selector.to_json}).getBoundingClientRect(); return [ box.left, box.top, box.right, box.bottom ] })()")
  end

  def content_left
    page.evaluate_script("(() => { const main = document.querySelector('.admin-shell__main'); return main.getBoundingClientRect().left + parseFloat(getComputedStyle(main).paddingLeft) })()")
  end
end
