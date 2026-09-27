require "test_helper"

class Pages::SaveTest < ActiveSupport::TestCase
  test "creates a page with translations in several languages" do
    result = Pages::Save.call(attributes: { parent: root_page, published: true },
      translations: { "en" => { title: "About", subtitle: "Who we are" }, "de" => { title: "Über uns" } })

    assert result.ok?
    assert_equal "Über uns", result.record.title(locale: :de)
    assert_equal "about", result.record.slug(locale: :en)
  end

  test "re-publishing a live page keeps its date; scheduled goes live now" do
    live = Page.create!(parent: root_page, title: "Live", published_at: 3.days.ago)
    original = live.published_at
    Pages::Save.call(live, attributes: { published: true })
    assert_in_delta original, live.reload.published_at, 1

    scheduled = Page.create!(parent: root_page, title: "Later", published_at: 1.day.from_now)
    Pages::Save.call(scheduled, attributes: { published: true })
    assert scheduled.reload.live?
  end

  test "published_at wins over published and false unpublishes" do
    page = Page.create!(parent: root_page, title: "P", published_at: 1.day.ago)
    at = 2.days.from_now.change(usec: 0)
    Pages::Save.call(page, attributes: { published: true, published_at: at })
    assert_equal at, page.reload.published_at

    Pages::Save.call(page, attributes: { published: false })
    assert_nil page.reload.published_at
  end

  test "a slug clash returns an error Result naming the language" do
    create_page(title: "About")

    result = Pages::Save.call(attributes: { parent: root_page }, translations: { "en" => { title: "About" } })

    assert_not result.ok?
    assert result.errors.any? { |message| message.match?(/EN/) }
  end

  test "invalid input comes back as a failed result, nothing saved" do
    parent = root_page
    before = Page.count

    result = Pages::Save.call(attributes: { parent: parent }, translations: { "en" => { title: "" } })

    assert_not result.ok?
    assert_equal before, Page.count
  end

  test "parent is only honoured on create -- an update can't move a page" do
    section = create_page(title: "Section")
    other = create_page(title: "Other")
    page = create_page(title: "Child", parent: section)

    result = Pages::Save.call(page, attributes: { parent: other, published: true },
      translations: { "en" => { title: "Child" } })

    assert result.ok?
    assert_equal section, page.reload.parent
  end
end
