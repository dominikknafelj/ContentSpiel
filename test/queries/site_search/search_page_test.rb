require "test_helper"

# The page a theme's own search box points at (search spec §7.3): the first
# page in reading order whose copy in force holds a Search block.
class SiteSearch::SearchPageTest < ActiveSupport::TestCase
  def search_page(locale: :en) = SiteSearch::SearchPage.new(now: Time.current, locale: locale).page

  def add_search(page)
    result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "search" })
    assert result.ok?, result.errors.to_sentence
    page
  end

  test "the first page in reading order whose live copy holds a Search block" do
    later = create_page(title: "Later")
    earlier = create_page(title: "Earlier")
    assert Pages::Move.call(earlier, parent: root_page, position: 0).ok?
    [ later, earlier ].each { |page| publish_changes(add_search(page)) }

    assert_equal earlier.id, search_page.id
    assert_predicate search_page, :readonly?
  end

  test "a page comes before its own subpages and a branch before the next sibling's" do
    parent = create_page(title: "Parent")
    child = create_page(title: "Child", parent: parent)
    sibling = create_page(title: "Sibling")
    [ sibling, child ].each { |page| publish_changes(add_search(page)) }

    assert_equal child.id, search_page.id
    publish_changes(add_search(parent))
    assert_equal parent.id, search_page.id
  end

  test "a Search block only in a page's rows or on a draft page is not it" do
    add_search(create_page(title: "Rows only"))
    publish_changes(create_page(title: "No block"))
    add_search(create_page(title: "Draft", published: false))

    assert_nil search_page

    held = add_search(create_page(title: "Held"))
    publish_changes(held)
    assert_equal held.id, search_page.id
  end

  test "none answers nil" do
    assert_nil search_page
  end

  test "a page without an address in the language is not it" do
    page = publish_changes(add_search(create_page(title: "Findable")))
    PublicPath.where(record_type: "Page", record_id: page.id, locale: "de").update_all(current: false)

    assert_equal page.id, search_page(locale: :en).id
    assert_nil search_page(locale: :de)
  end
end
