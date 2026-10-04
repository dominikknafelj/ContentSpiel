require "test_helper"

class Admin::EditorScreen::ChangedElsewhereComponentTest < ViewComponent::TestCase
  def render_bar(record, url: "/cs-studio/pages/1")
    render_inline(Admin::EditorScreen::ChangedElsewhereComponent.new(record: record, reload_url: url))
  end

  test "names who changed the record and when, and offers Reload" do
    page = create_page(title: "About")
    as(users(:two), channel: :admin) { Pages::Save.call(page, translations: { "en" => { subtitle: "New" } }) }

    render_bar(page)

    assert_selector "div#changed-elsewhere.bg-warn-tint[role=alert]"
    assert_text "Changed by two@example.com just now."
    assert_text "Your text is still here so you can copy it; reloading shows the latest version."
    assert_selector "a[href='/cs-studio/pages/1'][data-turbo-frame='_top']", text: "Reload"
  end

  test "a change to one of its blocks counts, a refused attempt does not" do
    page = create_page(title: "About")
    block = page.content_blocks.create!(block_type: :rich_text, position: 0)
    as(users(:two), channel: :admin) { ContentBlocks::Save.call(block, translations: { "en" => { body: rich_doc("Edited") } }) }
    as(users(:reader), channel: :admin) { Pages::Save.call(page, translations: { "en" => { subtitle: "Nope" } }) }

    render_bar(page)

    assert_text "Changed by two@example.com"
    assert_no_text users(:reader).email_address
  end

  test "prefers the newest change by someone else over the viewer's own later one" do
    page = create_page(title: "About")
    as(users(:two), channel: :admin) { Pages::Save.call(page, translations: { "en" => { subtitle: "Theirs" } }) }
    as(users(:one), channel: :admin) { Pages::Save.call(page, translations: { "en" => { subtitle: "Mine" } }) }

    Current.set(session: users(:one).sessions.create!) { render_bar(page) }

    assert_text "Changed by two@example.com"
  end

  test "without any audit event it says so, without a name" do
    # An id no event names (a record saved straight through the model).
    render_bar(Page.new(id: 0))

    assert_text "Changed elsewhere."
    assert_no_text "Changed by"
  end
end
