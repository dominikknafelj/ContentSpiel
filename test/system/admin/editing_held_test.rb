require "application_system_test_case"

# A page whose block and settings someone else holds is drawn read-only in a
# real browser (live-editing Task 7): the strip says who, a text field cannot
# be typed in, the rich-text field has no toolbar and no caret, and the form
# sends no save. Nothing claims yet (Task 8), so the reservation is a row made
# here. A full load carries no tab id, so every hold is somebody else's.
class Admin::EditingHeldSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    users(:one).update!(name: "Olga Braun")
    @dana = users(:two).tap { |user| user.update!(name: "Dana Weiss") }
    @page = create_page(title: "Pricing", published: false)
    @text = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" }, translations: { "en" => { body: { "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "As written" } ] } ] } } }).record
    @list = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "post_list", settings: { "limit" => 3 } }).record
    Editing::Reservation.claim(subject: @text, record: @page, user: @dana, tab: "tab-bbbbbbbb", now: Time.current)
    Editing::Reservation.claim(subject: @list, record: @page, user: @dana, tab: "tab-bbbbbbbb", now: Time.current)
    Editing::Reservation.claim(subject: @page, record: @page, user: @dana, tab: "tab-bbbbbbbb", now: Time.current)
    sign_in_via_form(users(:one))
  end

  test "a held block and the held page settings are read-only: the strip names the holder, nothing can be typed, no toolbar, no save" do
    visit "/cs-studio/pages/#{@page.id}"
    await_notes_live

    assert_selector "#block-#{@text.id}-hold [data-editing-kind=held]", text: "Dana Weiss is editing this block"
    assert_selector "#page-hold [data-editing-kind=held]", text: "Dana Weiss is editing the page settings"
    assert_no_selector "#content_block_#{@text.id} [role=toolbar]"
    assert_selector "#content_block_#{@text.id} .ProseMirror[contenteditable=false], #content_block_#{@text.id} .ProseMirror:not([contenteditable=true])"

    find("#content_block_#{@text.id} .ProseMirror").click
    find("#content_block_#{@text.id} .ProseMirror").send_keys("ZZZ")
    limit = find("#block-#{@list.id}-limit")
    assert_selector "#block-#{@list.id}-limit[readonly]"
    limit.send_keys("9")
    title = find("#page-title")
    title.send_keys("ZZZ")
    find("body").click
    await_frames

    assert_equal "3", limit.value
    assert_equal "Pricing", title.value
    assert_no_text "ZZZ"
    assert_writes_settled
    body = @text.reload.body_document(locale: "en").to_json
    assert_includes body, "As written"
    assert_not_includes body, "ZZZ"
    assert_equal 3, @list.reload.settings["limit"].to_i
    assert_equal "Pricing", @page.reload.title
    assert_no_selector "[data-controller~='admin--saving--autosave']"
  end

  test "Take over in the strip does nothing yet: it neither submits nor navigates" do
    visit "/cs-studio/pages/#{@page.id}"
    await_notes_live
    url = page.current_url

    find("#block-#{@text.id}-hold button", text: "Take over").click
    await_frames

    assert_equal url, page.current_url
    assert_selector "#block-#{@text.id}-hold [data-editing-kind=held]"
  end

  def resource_requests = page.evaluate_script("performance.getEntriesByType('resource').map((entry) => entry.name).filter((name) => name.includes('/content_blocks/') || name.includes('/pages/'))")

  test "Enter in a held form's text field and in its read-only rich text sends no request and navigates nowhere" do
    visit "/cs-studio/pages/#{@page.id}"
    await_notes_live
    page.execute_script("window.__marker = 'same document'")
    url = page.current_url
    before = resource_requests

    find("#block-#{@list.id}-limit").send_keys(:enter)
    find("#page-title").send_keys(:enter)
    find("#content_block_#{@text.id} .ProseMirror").click
    find("#content_block_#{@text.id} .ProseMirror").send_keys(:enter)
    await_frames

    assert_equal "same document", page.evaluate_script("window.__marker")
    assert_equal url, page.current_url
    assert_equal before, resource_requests
    assert_writes_settled
    assert_equal 3, @list.reload.settings["limit"].to_i
  end
end
