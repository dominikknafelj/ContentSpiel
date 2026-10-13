require "test_helper"

# `PostGraph.paths`: the pages' current addresses for the graph's cards and
# rows, in the viewer's language or else the default one.
class PostGraph::PathsTest < ActiveSupport::TestCase
  test "a page's address is its current path in the language asked for, else in the default language" do
    both = create_page(title: "About", translations: { de: { title: "Über uns", slug: "ueber-uns" } })
    english = create_page(title: "Contact")
    PublicPath.where(record_type: "Page", record_id: english.id, locale: "de").delete_all # version: none (a test removes an address)

    assert_equal({ both.id => "/ueber-uns", english.id => "/contact" }, PostGraph.paths([ both.id, english.id ], locale: :de))
    assert_equal({ both.id => "/about", english.id => "/contact" }, PostGraph.paths([ both.id, english.id ], locale: "en"))
    assert_equal({ both.id => "/about" }, PostGraph.paths(Page.where(id: both.id).select(:id), locale: :en), "a relation of ids is taken as a list is")
  end

  test "an old address is not handed up, and a page with none is not in the answer" do
    page = create_page(title: "Old name")
    PublicPath.where(record_type: "Page", record_id: page.id, locale: "en").update_all(current: false) # version: none (a test sets an address aside)
    draft = Page.create!(parent: root_page, title: "No address yet")
    PublicPath.where(record_type: "Page", record_id: draft.id).delete_all # version: none (a test removes an address)

    answer = PostGraph.paths([ page.id, draft.id, 0 ], locale: :en)

    assert_not_includes answer.values, "/old-name"
    assert_not_includes answer.keys, draft.id
    assert_not_includes answer.keys, 0
    assert_empty PostGraph.paths([], locale: :en)
  end

  test "it costs one statement, for 3 pages and for 30" do
    3.times { |index| create_page(title: "Few #{index}") }
    four = Page.pluck(:id)
    few = capture_sql { assert_equal 4, PostGraph.paths(four, locale: :de).size }
    27.times { |index| create_page(title: "Many #{index}") }
    ids = Page.pluck(:id)
    many = capture_sql { assert_equal 31, PostGraph.paths(ids, locale: :de).size }

    assert_equal 1, few.size, few.join("\n")
    assert_equal 1, many.size, many.join("\n")
  end
end
