require "test_helper"

class Admin::EditorScreen::ChangedElsewhereComponentTest < ViewComponent::TestCase
  def render_bar(record, since: nil, url: "/cs-studio/pages/1")
    render_inline(Admin::EditorScreen::ChangedElsewhereComponent.new(record: record, reload_url: url, since: since))
  end

  test "names who changed the record and when, and offers Reload" do
    page = create_page(title: "About")
    base = page.updated_at
    travel 2.seconds
    as(users(:two), channel: :admin) { Pages::Save.call(page, translations: { "en" => { subtitle: "New" } }) }

    render_bar(page, since: base)

    assert_selector "div#changed-elsewhere.bg-warn-tint[role=alert]"
    assert_text "Changed by two@example.com just now."
    assert_text "Your text is still here so you can copy it; reloading shows the latest version."
    assert_selector "a[href='/cs-studio/pages/1'][data-turbo-frame='_top']", text: "Reload"
  end

  test "a change to one of a page's blocks does not count (the settings form's base ignores it), and a refused attempt does not either" do
    page = create_page(title: "About")
    block = page.content_blocks.create!(block_type: :rich_text, position: 0)
    base = page.reload.updated_at
    travel 2.seconds
    as(users(:two), channel: :admin) { ContentBlocks::Save.call(block, translations: { "en" => { body: rich_doc("Edited") } }) }
    as(users(:reader), channel: :admin) { Pages::Save.call(page, translations: { "en" => { subtitle: "Nope" } }) }

    render_bar(page, since: base)

    assert_text "Changed elsewhere."
    assert_no_text "Changed by"
    assert_no_text users(:reader).email_address
  end

  test "prefers the newest change by someone else over the viewer's own later one" do
    page = create_page(title: "About")
    base = page.updated_at
    travel 2.seconds
    as(users(:two), channel: :admin) { Pages::Save.call(page, translations: { "en" => { subtitle: "Theirs" } }) }
    as(users(:one), channel: :admin) { Pages::Save.call(page, translations: { "en" => { subtitle: "Mine" } }) }

    Current.set(session: users(:one).sessions.create!) { render_bar(page, since: base) }

    assert_text "Changed by two@example.com"
  end

  test "an event the form had already loaded is not what made it stale: the viewer's own later save in another tab reads as such" do
    page = create_page(title: "About")
    as(users(:two), channel: :admin) { Pages::Save.call(page, translations: { "en" => { subtitle: "B at 10:00" } }) }
    base = page.reload.updated_at
    travel 6.minutes
    as(users(:one), channel: :admin) { Pages::Save.call(page, translations: { "en" => { subtitle: "A in another tab" } }) }

    Current.set(session: users(:one).sessions.create!) { render_bar(page, since: base) }

    assert_text "Changed in another tab or window just now."
    assert_no_text "two@example.com"
  end

  test "with no event after the base it says so, without a name" do
    page = create_page(title: "About")
    as(users(:two), channel: :admin) { Pages::Save.call(page, translations: { "en" => { subtitle: "Before the form loaded" } }) }

    render_bar(page, since: page.reload.updated_at)

    assert_text "Changed elsewhere."
    assert_no_text "Changed by"
  end

  test "a record no event names reads without a name" do
    render_bar(Page.new(id: 0))

    assert_text "Changed elsewhere."
  end
end
