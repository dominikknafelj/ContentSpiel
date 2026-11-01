require "application_system_test_case"

# The Card block's card in the page editor, in a browser: added from the
# picker, its title, text and link typed and saved by themselves and back
# after a reload (the icon select only under a theme that declares icons),
# and a second person's card read-only while the first holds it, the icon
# select disabled.
class Admin::CardBlockSystemTest < ApplicationSystemTestCase
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

  def field(block, name) = find("#block-#{block.id}-#{name}")

  test "a Card added from the picker is typed into, saved by itself and back after a reload" do
    open_editor
    within("#block-picker-end") { press "Card" }
    # wait: the card is the answer to the request that creates the block, on a runner with two slow cores.
    assert_selector ".admin-block-card input[name='block[settings][title]']", wait: 8
    block = @page.content_blocks.sole
    await_admin_controllers

    assert_no_selector "#block-#{block.id}-icon", wait: 0
    field(block, "title").set("Our services")
    field(block, "text").set("What we do, in a line.")
    field(block, "link").set("/about")
    assert_writes_settled

    settings = block.reload.settings_object(locale: "en")
    assert_equal [ "Our services", "What we do, in a line.", "/about" ], [ settings.title, settings.text, settings.link ]

    open_editor
    assert_equal "Our services", field(block, "title").value
    assert_equal "/about", field(block, "link").value
  end

  test "while one person types a card's title, a second person's card is read-only, the icon select disabled" do
    with_choices_theme do
      block = @page.content_blocks.create!(block_type: "card", position: 0, settings: { "icon" => "brush" })
      open_editor
      field(block, "title").set("Mind the gap")
      assert_writes_settled
      assert_equal "Mind the gap", block.reload.settings_object(locale: "en").title

      using_session(:dana) do
        sign_in_via_form(users(:two))
        open_editor

        assert_selector "#content_block_#{block.id}[data-editing-held=true] [data-editing-kind=held]", text: "Olga Braun is editing this block"
        assert_selector "#block-#{block.id}-title[readonly]"
        assert_selector "#block-#{block.id}-icon[disabled]"
        assert_equal "Mind the gap", field(block, "title").value
      end
    end
  end
end
