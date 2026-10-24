require "application_system_test_case"

# The Note block's card in the page editor, in a browser (note block spec,
# "CS Studio"): the kind chosen from the keyboard on a segmented control,
# the title's placeholder following the kind before the save, the card's
# icon following it after the save (plan ruling 12), the title and
# the text typed and saved by themselves and back after a reload; and a
# second person's card read-only while the first holds it.
class Admin::NoteBlockSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    users(:one).update!(name: "Olga Braun")
    @page = create_page(title: "Guide", published: false)
    sign_in_via_form(users(:one))
  end

  def open_editor
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
    await_notes_live
  end

  def kind(block, value) = find("#block-#{block.id}-kind-#{value}", visible: :all)

  def title_field(block) = find("#block-#{block.id}-title")

  test "a Note added from the picker is a Note; its kind is chosen with the arrow keys, the title's placeholder follows it, and all of it is saved and back after a reload" do
    open_editor
    within("#block-picker-end") { press "Note" }
    # wait: the card is the answer to the request that creates the block, on a runner with two slow cores.
    assert_selector ".admin-block-card fieldset input[type=radio][name='block[settings][kind]']", visible: :all, count: 4, wait: 8
    block = @page.content_blocks.sole
    await_admin_controllers

    assert kind(block, "note").checked?
    assert_equal "Note", title_field(block)[:placeholder]

    assert_selector "#block-#{block.id}-icon-card[data-block-icon=info]"
    kind(block, "note").execute_script("this.focus()") # focus: an sr-only radio has no box a click lands on
    page.driver.browser.keyboard.type(:right) # the focused radio gets the key; a node's own send_keys would click it first
    assert_selector "#block-#{block.id}-kind-tip:checked", visible: :all
    assert_equal "Tip", title_field(block)[:placeholder], "the placeholder follows the kind before the save"
    # Plan ruling 12: the card's icon follows the kind once the save's answer is here.
    assert_selector "#block-#{block.id}-icon-card[data-block-icon=lightbulb]"

    title_field(block).set("Before you publish")
    find("#content_block_#{block.id} .ProseMirror").send_keys("Mind the address.")
    assert_writes_settled
    block.reload
    assert_equal "tip", block.settings["kind"]
    assert_equal({ "en" => { "title" => "Before you publish" } }, block.translated_settings)
    assert_equal [ "Mind the address." ], block.body_document(locale: :en).plain_paragraphs

    open_editor
    assert kind(block, "tip").checked?
    assert_equal "Before you publish", title_field(block).value
    assert_equal "Tip", title_field(block)[:placeholder]
    assert_selector "#block-#{block.id}-icon-card[data-block-icon=lightbulb]", count: 1
  end

  test "while one person types a note's title, a second person's card is read-only: every kind's button disabled, the title read-only with the same text" do
    block = @page.content_blocks.create!(block_type: "note", position: 0, settings: { "kind" => "warning" })
    open_editor
    title_field(block).set("Mind the gap")
    assert_writes_settled
    assert_equal "Mind the gap", block.reload.settings_object(locale: "en").title

    using_session(:dana) do
      sign_in_via_form(users(:two))
      open_editor

      assert_selector "#content_block_#{block.id}[data-editing-held=true] [data-editing-kind=held]", text: "Olga Braun is editing this block"
      assert_selector "#block-#{block.id}-title[readonly]"
      assert_equal "Mind the gap", title_field(block).value
      BlockTypes::Note::KINDS.each_key { |value| assert kind(block, value).disabled?, value }
      assert kind(block, "warning").checked?
    end
  end

  # A gap earlier reviews left: the script alone, before any save's answer.
  test "a kind pressed in the browser changes the title's placeholder in the same task, before any save can have answered" do
    block = @page.content_blocks.create!(block_type: "note", position: 0, settings: { "kind" => "note" })
    open_editor
    placeholder = page.evaluate_script(<<~JS)
      (() => {
        document.querySelector("#block-#{block.id}-kind-warning").click()
        return document.querySelector("#block-#{block.id}-title").placeholder
      })()
    JS
    assert_equal "Warning", placeholder
    assert_writes_settled
    assert_equal "warning", block.reload.settings["kind"]
  end

  # The other gap: a save's icon stream replaces the icon span and nothing else.
  test "a save's icon stream from another block's kind change leaves an open card with unsaved text as it is: the same field, the same text" do
    first = @page.content_blocks.create!(block_type: "note", position: 0, settings: { "kind" => "note" })
    second = @page.content_blocks.create!(block_type: "note", position: 1, settings: { "kind" => "note" })
    open_editor
    page.execute_script("window.firstTitle = document.querySelector('#block-#{first.id}-title')")
    title_field(first).send_keys("Typed, not yet saved")
    kind(second, "note").execute_script("this.focus()") # focus: an sr-only radio has no box a click lands on
    page.driver.browser.keyboard.type(:right)
    assert_selector "#block-#{second.id}-icon-card[data-block-icon=lightbulb]"
    assert page.evaluate_script("window.firstTitle === document.querySelector('#block-#{first.id}-title')"), "the open card's field was replaced"
    assert_equal "Typed, not yet saved", title_field(first).value
    assert_selector "#block-#{first.id}-icon-card[data-block-icon=info]"
    assert_writes_settled
    assert_equal({ "en" => { "title" => "Typed, not yet saved" } }, first.reload.translated_settings)
    assert_equal "tip", second.reload.settings["kind"]
  end
end
