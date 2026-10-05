require "test_helper"

class StarterContents::EnsureHomeTest < ActiveSupport::TestCase
  test "creates a published root page with a welcome block" do
    Page.destroy_all
    home = StarterContents::EnsureHome.call(locale: "en").record

    assert_nil home.parent_id
    assert home.published_at.present?
    assert_equal [ "rich_text" ], home.content_blocks.map(&:block_type)
    document = home.content_blocks.first.body_document(locale: "en")
    assert_kind_of RichText::Document, document
    assert_includes document.to_markdown, "Welcome to your new site"
  end

  test "keeps an existing homepage and its blocks" do
    Page.destroy_all
    existing = Page.create!(page_type: :standard, title: "Mine", slug: "", published_at: Time.current)
    existing.content_blocks.create!(block_type: :post_list, position: 0)

    assert_no_difference [ "Page.count", "ContentBlock.count" ] do
      assert_equal existing, StarterContents::EnsureHome.call(locale: "en").record
    end
  end

  test "an actor without the rights is refused with one access.denied, and nothing is written" do
    Page.destroy_all
    result = nil
    assert_no_difference [ "Page.count", "ContentBlock.count" ] do
      result = as(users(:reader)) { StarterContents::EnsureHome.call(locale: "en") }
    end

    assert_predicate result, :denied?
    assert_equal [ "access.denied" ], Audit::Event.pluck(:action)
  end

  test "the setup channel with no actor is trusted" do
    Page.destroy_all

    assert as(nil, channel: :setup) { StarterContents::EnsureHome.call(locale: "en") }.ok?
  end
end
