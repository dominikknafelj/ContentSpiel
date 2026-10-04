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
    # now. Asserting an absence needs the wait itself.
    sleep 1.5

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

    find(".ProseMirror figure.admin-rich-text-image").execute_script("this.click()")
    sleep 0.5
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
end
