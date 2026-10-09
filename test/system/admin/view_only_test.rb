require "application_system_test_case"

# The view-only editor (access-control design spec §5 "Everywhere", Review
# Focus 4): a read-only user opening a post sees "View only", every field
# disabled -- the Tiptap editor included, which a `<fieldset disabled>`
# alone wouldn't reach -- and nothing they do sends a PATCH, because
# `admin--autosave` isn't attached at all. System-level because "sends no
# request" is only observable in a real browser: PATCHes are counted with
# the same `window.fetch` hook `Admin::AutosaveSystemTest` uses.
class Admin::ViewOnlySystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @post = create_post(title: "Hands off", published: false)
    Posts::Save.call(@post, translations: { "en" => { body: rich_doc("Original body") } })
    sign_in_via_form(users(:reader))
  end

  # Task 19's visual difference 9: the chip input's frame is a div, so the
  # sunken look of a disabled field missed it and it kept a white frame around
  # a sunken inner field.
  test "the tag chip input's frame is as sunken as the other disabled fields" do
    visit "/cs-studio/posts/#{@post.id}"
    await_admin_controllers
    background = ->(selector) { page.evaluate_script("getComputedStyle(document.querySelector(#{selector.to_json})).backgroundColor") }
    assert_equal background.call("#post-title"), background.call(".admin-chip-field")
  end

  test "a read-only user's post editor is view only and never autosaves" do
    visit "/cs-studio/posts/#{@post.id}"
    await_admin_controllers

    page.execute_script(<<~JS)
      const originalFetch = window.fetch
      window.__writes = 0
      window.fetch = (url, options = {}) => {
        if ((options.method || "GET").toUpperCase() !== "GET") window.__writes += 1
        return originalFetch(url, options)
      }
    JS

    assert_selector "[data-view-only]", text: "View only"
    assert_no_selector "[data-controller~='admin--autosave']"
    assert_no_button "Publish"
    assert_no_selector "button[aria-label='More actions']"
    assert_no_button "Delete"

    title = find_field("Title", disabled: true)
    assert title.disabled?

    editor = find(".admin-rich-text-content[contenteditable='false']")
    editor.click
    page.driver.browser.keyboard.type("typed ")

    # What the autosave controller would have listened for, fired by hand
    # on the disabled title: with nothing attached, nothing answers.
    page.execute_script(<<~JS)
      const field = document.getElementById("post-title")
      field.dispatchEvent(new Event("input", { bubbles: true }))
      field.dispatchEvent(new FocusEvent("focusout", { bubbles: true }))
    JS

    # Past the 1000ms autosave debounce: a queued save would have fired by
    # now. The page has no autosave form, so the write queue has nothing that
    # could report the debounce as over; asserting an absence needs the wait itself.
    sleep 1.1 # sleep: the autosave debounce is 1 s; a view-only page has no registered form, so nothing marks the expiry of a timer that must not exist

    assert_equal 0, page.evaluate_script("window.__writes")
    assert_no_text "typed"
    assert_text "Original body"
    assert_equal "Hands off", @post.reload.title
  end

  test "a read-only user clicking an image in the body opens no dialog" do
    asset = create_media_asset
    Posts::Save.call(@post, translations: { "en" => { body: { "type" => "doc", "content" => [ { "type" => "image", "attrs" => { "asset_id" => asset.id, "alt" => "", "caption" => "" } } ] } } })
    visit "/cs-studio/posts/#{@post.id}"
    await_admin_controllers

    find(".ProseMirror figure.admin-rich-text-image").click
    await_frames # a click handler that opened the dialog has run by now
    assert_no_selector "dialog[open]"
  end

  test "a read-only user's page editor says why, shows no tools, and cannot type" do
    page_record = create_page(title: "Look only")
    page_record.content_blocks.create!(block_type: :rich_text, position: 0)
    visit "/cs-studio/pages/#{page_record.id}"
    await_admin_controllers

    assert_selector "[data-view-only-hint]", text: "You can view this page but not change it."
    assert_selector "#editor-notice"
    assert_no_selector "[role=toolbar]"
    assert_no_selector ".admin-block-card__handle"
    assert_no_selector "button[aria-label='Block actions'], summary[aria-label='Block actions']"
    assert_no_text "Add block"
    assert_no_selector "[data-controller~='admin--autosave']"
    assert_selector ".admin-view-only"
    assert find_field("Title", disabled: true).disabled?
  end

  # Sections spec §1: view only stays view only inside a section too. A tile
  # can still be opened -- reading a block's fields changes nothing -- and
  # the form it shows is the disabled one, with no autosave.
  test "a read-only user sees a section's tiles and can open a form, with nothing to change and nothing sent" do
    page_record = create_page(title: "Banded, hands off")
    section = page_record.content_blocks.create!(block_type: "section", position: 0)
    block = page_record.content_blocks.create!(block_type: "image", section: section, section_column: 1, position: 0)
    visit "/cs-studio/pages/#{page_record.id}"
    await_admin_controllers

    assert_selector ".admin-block-tile", count: 1
    assert_no_selector ".admin-block-tile__grip"
    assert_no_selector "[id^='block-picker-#{section.id}-']"
    assert_no_selector ".admin-section-card button[aria-label='Section actions']"
    assert_no_selector ".admin-section-card button[aria-label='Block actions']"
    assert_no_selector ".admin-section-card dialog", visible: :all
    find("##{ActionView::RecordIdentifier.dom_id(block)} .admin-block-tile__face").click
    assert_selector "#block-#{block.id}-panel fieldset[disabled]"
    assert_no_selector "#block-#{block.id}-panel form[data-controller~='admin--autosave']"
    assert_no_selector "[data-controller~='admin--autosave']", visible: :all
  end

  test "a read-only user's translation tab lists a section's blocks disabled, with nothing that writes" do
    with_locales(%w[en de], default: "en") do
      page_record = create_page(title: "Banded, hands off")
      section = page_record.content_blocks.create!(block_type: "section", position: 0)
      block = page_record.content_blocks.create!(block_type: "image", section: section, section_column: 1, position: 0, caption: "Original caption")
      visit "/cs-studio/pages/#{page_record.id}?locale=de"
      await_admin_controllers

      assert_selector ".admin-section-group > .admin-block-card[data-block-id='#{block.id}'] fieldset[disabled]"
      assert_selector ".admin-section-group .admin-translation-pair", text: "Original caption"
      assert find_field("block-#{block.id}-caption", disabled: true).disabled?
      assert_no_selector "[data-controller~='admin--autosave']", visible: :all
      assert_no_selector ".admin-section-group button[aria-label='Block actions'], .admin-block-card__handle", visible: :all
      assert_no_selector ".admin-section-group dialog", visible: :all
    end
  end

  test "a read-only user sees a section whose type is gone with its tiles and nothing that deletes" do
    page_record = create_page(title: "Banded, hands off")
    section = page_record.content_blocks.create!(block_type: "section", position: 0)
    page_record.content_blocks.create!(block_type: "image", section: section, section_column: 1, position: 0)
    section.update_columns(block_type: "gone/section")
    visit "/cs-studio/pages/#{page_record.id}"
    await_admin_controllers

    assert_selector ".admin-section-card.border-danger", text: "Unavailable type — gone/section"
    assert_selector ".admin-block-tile", count: 1
    assert_no_button "Delete block…"
    assert_no_selector ".admin-section-card dialog", visible: :all
    assert_no_selector ".admin-block-tile__grip"
  end
end
