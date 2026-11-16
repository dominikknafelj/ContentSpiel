require "test_helper"

# A tag's listing page (search spec §4.4): the first visible page in reading
# order, with an address in the language, whose copy in force holds a list
# block filtered by that tag and by no content type.
class SiteSearch::TagPageTest < ActiveSupport::TestCase
  def tag_pages(ids, locale: "en") = SiteSearch::TagPage.for(ids, locale: locale, now: Time.current)

  # A page holding a post list filtered by `tag`, and by `content_type` when
  # one is given, published with the list in its copy.
  def page_with_post_list(tag:, content_type: nil, published: true, title: "Listing #{Page.count}", parent: root_page)
    page = create_page(title: title, published: published, parent: parent)
    settings = { "tag" => tag.name, "content_type" => content_type.to_s }
    result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list", settings: settings })
    assert result.ok?, result.errors.to_sentence
    publish_changes(page) if published
    page.reload
  end

  test "a tag suggestion goes to the first visible page whose copy lists that tag with no content type, else to a search for it" do
    tag = Tag.create!(name: "deployment")
    page_with_post_list(tag: tag, content_type: "blog")
    assert_empty tag_pages([ tag.id ]), "a list that also names a content type lists only some of the tag's posts"

    listing = page_with_post_list(tag: tag)
    assert_equal listing.id, tag_pages([ tag.id ])[tag.id].id
    assert_predicate tag_pages([ tag.id ])[tag.id], :readonly?, "the page as published"
  end

  # A trashed listing page is the request's test, where the suggestion then
  # searches for the tag (test/controllers/site_search/suggestions_controller_test.rb).
  test "a draft listing page is not the tag's page" do
    tag = Tag.create!(name: "deployment")
    page_with_post_list(tag: tag, published: false)
    assert_empty tag_pages([ tag.id ])
  end

  test "a list only in a page's rows, or under a draft page, is not the tag's page" do
    tag = Tag.create!(name: "deployment")
    rows_only = create_page(title: "Rows only")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: rows_only), attributes: { block_type: "post_list", settings: { "tag" => tag.name } }).ok?
    hidden = create_page(title: "Hidden", published: false)
    page_with_post_list(tag: tag, parent: hidden)

    assert_empty tag_pages([ tag.id ])
  end

  test "the first in reading order, per tag, and a page without an address in the language is not it" do
    one = Tag.create!(name: "one")
    two = Tag.create!(name: "two")
    later = page_with_post_list(tag: one, title: "Later")
    earlier = page_with_post_list(tag: one, title: "Earlier")
    assert Pages::Move.call(earlier, parent: root_page, position: 0).ok?
    other = page_with_post_list(tag: two, title: "Other")

    found = tag_pages([ one.id, two.id ])
    assert_equal({ one.id => earlier.id, two.id => other.id }, found.transform_values(&:id))

    PublicPath.where(record_type: "Page", record_id: earlier.id, locale: "en").update_all(current: false) # version: none (a test takes an address away)
    assert_equal later.id, tag_pages([ one.id ])[one.id].id
  end

  test "with_search_page answers the listings and the search page as for and SearchPage do" do
    tag = Tag.create!(name: "deployment")
    listing = page_with_post_list(tag: tag)
    search = create_page(title: "Search")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: search), attributes: { block_type: "search" }).ok?
    publish_changes(search)

    listings, page = SiteSearch::TagPage.with_search_page([ tag.id ], locale: "en", now: Time.current)
    assert_equal({ tag.id => listing.id }, listings.transform_values(&:id))
    assert_equal SiteSearch::SearchPage.new(now: Time.current, locale: "en").page.id, page.id
    assert_predicate page, :readonly?, "the page as published"
    assert_equal [ {}, page.id ], SiteSearch::TagPage.with_search_page([], locale: "en", now: Time.current).then { [ _1, _2.id ] }
  end

  test "no tags ask nothing" do
    assert_queries_count(0) { assert_equal({}, tag_pages([])) }
  end
end
