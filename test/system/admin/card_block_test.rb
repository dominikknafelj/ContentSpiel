require "application_system_test_case"

# The Card block's card in the page editor, in a browser: added from the
# picker, its title, text and link typed and saved by themselves and back
# after a reload (the icon select offers the default theme's twelve icons,
# and a theme's own set replaces them),
# and a second person's card read-only while the first holds it, the icon
# select disabled; and its library image chosen with the picker, saved and
# back after a reload, and read-only for the second person too.
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
    add_block "Card"
    # wait: the card is the answer to the request that creates the block, on a runner with two slow cores.
    assert_selector ".admin-block-card input[name='block[settings][title]']", wait: 8
    block = @page.content_blocks.sole
    await_admin_controllers

    assert_equal [ "No icon", "Arrow right", "Check", "Star", "Heart", "Mail", "Map pin", "Calendar", "User", "Shield", "Briefcase", "Clock", "Globe" ],
      field(block, "icon").all("option").map(&:text)
    field(block, "icon").select("Star")
    field(block, "title").set("Our services")
    field(block, "text").set("What we do, in a line.")
    field(block, "link").set("/about")
    assert_writes_settled

    settings = block.reload.settings_object(locale: "en")
    assert_equal [ "star", "Our services", "What we do, in a line.", "/about" ], [ settings.icon, settings.title, settings.text, settings.link ]

    open_editor
    assert_equal "Star", field(block, "icon").find("option[selected]").text
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

  test "an image chosen on a card with the picker is saved by itself and back after a reload, and Remove takes it away" do
    asset = create_media_asset(filename: "tiny.png")
    asset.update!(title: "Harbour photo", alt: "The harbour")
    block = @page.content_blocks.create!(block_type: "card", position: 0)
    open_editor
    section = "#block-#{block.id}-image-section"

    within(section) { click_on "Choose image" }
    within("dialog[open]") do
      click_on "Harbour photo"
      click_on "Use image"
    end
    refute_selector "dialog[open]"
    assert_eventually(wait: 10, message: "the pick was saved") { block.reload.media_asset_id == asset.id }
    assert_selector "#block-#{block.id}-alt[placeholder='The harbour']"
    assert_writes_settled

    open_editor
    assert_selector "#{section} input[type=hidden][value='#{asset.id}']", visible: :all
    within(section) { assert_button "Change image" }
    assert_selector "#block-#{block.id}-alt[placeholder='The harbour']"

    field(block, "alt").set("Our own words")
    assert_writes_settled
    assert_equal "Our own words", block.reload.alt(locale: "en")

    within(section) { click_on "Remove image" }
    assert_eventually(wait: 10, message: "the removal was saved") { block.reload.media_asset_id.nil? }
  end

  test "while one person holds a card with an image, a second person cannot change the image or its alt" do
    asset = create_media_asset(filename: "tiny.png")
    block = @page.content_blocks.create!(block_type: "card", position: 0, media_asset: asset)
    open_editor
    field(block, "title").set("Mind the gap")
    assert_writes_settled

    using_session(:dana) do
      sign_in_via_form(users(:two))
      open_editor

      assert_selector "#content_block_#{block.id}[data-editing-held=true]"
      assert_selector "#block-#{block.id}-alt[readonly]"
      assert_no_selector "#block-#{block.id}-image-section button:not([disabled])", visible: :visible
    end
  end
end
