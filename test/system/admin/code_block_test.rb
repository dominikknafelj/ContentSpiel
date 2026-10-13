require "application_system_test_case"

# The Code block's card in the page editor, in a browser (code block spec
# §3): typed into and saved by itself with its white space as typed, refused
# over the limit with the text left in the field, and read-only for a second
# person while the first holds it.
class Admin::CodeBlockSystemTest < ApplicationSystemTestCase
  TYPED = "    indented first\n  second".freeze

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
  def paste(block, count)
    page.execute_script("const field = document.getElementById(arguments[0]); field.value = 'x'.repeat(arguments[1]); field.dispatchEvent(new Event('input', { bubbles: true }))", code_id(block), count)
  end

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
    assert_selector "##{code_id(block)}-count", text: "18,412 of 20,000"
    assert_writes_settled
    assert_equal 18_412, block.reload.settings["code"].length

    paste(block, 20_001)
    assert_selector "##{code_id(block)}-errors", text: "Code is too long (maximum is 20000 characters)"
    assert_selector "##{code_id(block)}-count.text-warn-ink", text: "20,001 of 20,000"
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
end
