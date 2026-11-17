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

  test "an older copy that held a Search block no longer makes a page the search page" do
    page = publish_changes(add_search(create_page(title: "Was the search page")))
    assert_equal page.id, search_page.id

    assert ContentBlocks::Destroy.call(page.content_blocks.sole).ok?
    publish_changes(page)
    assert Publishing::Version.of(page).where(holds_search: true).exists?, "the copy that held the block is still in the history"
    assert_nil search_page, "only the copy in force counts"
  end

  test "a Search block in a change scheduled for later is not it until its time, and a trashed page is never it" do
    page = publish_changes(create_page(title: "Scheduled"))
    publish_changes(add_search(page), at: 2.days.from_now)
    assert_nil search_page
    travel 3.days do
      assert_equal page.id, search_page.id
    end

    trashed = publish_changes(add_search(create_page(title: "Trashed")))
    assert_equal trashed.id, search_page.id
    assert Trash::Move.call(trashed).ok?
    assert_nil search_page
  end

  test "taking a copy writes whether it holds a Search block" do
    page = publish_changes(create_page(title: "Flagged"))
    assert_not Publishing::Version.of(page).order(:id).last.holds_search
    publish_changes(add_search(page))
    assert Publishing::Version.of(page).order(:id).last.holds_search
  end

  # The holders were once found by testing `blocks @> [{"block_type":
  # "search"}]` of the copies in force as a filter of the whole table, which
  # Postgres ran as a scan reading every copy's `blocks`, the history's too
  # (`FirstHolder.copies_holding`).
  test "the search page is found from the flags and never reads a copy's blocks" do
    page = publish_changes(add_search(create_page(title: "Findable")))
    3.times { publish_changes(page) }

    statements = capture_sql { assert_equal page.id, search_page.id }.select { |sql| sql.include?(%("published_versions")) }
    assert statements.any? { |sql| sql.include?(%("published_versions"."holds_search" = TRUE)) }, "the holders are read from the flag"
    statements.each { |sql| assert_not_includes sql, %("published_versions"."blocks"), "no statement reads a copy's blocks: #{sql}" }
  end
end
