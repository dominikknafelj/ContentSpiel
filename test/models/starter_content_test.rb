require "test_helper"

class StarterContentTest < ActiveSupport::TestCase
  test "ensure_home! creates a published root page with a welcome block" do
    home = StarterContent.ensure_home!(locale: "en")

    assert_nil home.parent_id
    assert home.published_at.present?
    assert_equal [ "rich_text" ], home.content_blocks.map(&:block_type)
    document = home.content_blocks.first.body_document(locale: "en")
    assert_kind_of RichText::Document, document
    assert_includes document.to_markdown, "Welcome to your new site"
  end

  test "sample posts get JSON body documents in the given locale" do
    StarterContent.create_pages_and_posts!(locale: "de")

    Post.find_each do |post|
      assert_not post.body_document(locale: "de").blank?, "#{post.content_type} sample has no body"
      assert_empty post.body_document(locale: "de").validate
    end
  end

  test "ensure_home! keeps an existing homepage and its blocks" do
    existing = Page.create!(page_type: :standard, title: "Mine", slug: "", published_at: Time.current)
    existing.content_blocks.create!(block_type: :post_list, position: 0)

    assert_no_difference [ "Page.count", "ContentBlock.count" ] do
      assert_equal existing, StarterContent.ensure_home!(locale: "en")
    end
  end

  test "create_pages_and_posts! adds Blog, Resume and Now pages with one sample post each" do
    StarterContent.create_pages_and_posts!(locale: "en")

    home = Page.find_by(parent_id: nil)
    slugs = home.children.map(&:slug)
    assert_equal %w[blog now resume], slugs.sort
    assert_equal %w[blog now_update resume_entry], Post.pluck(:content_type).sort
    assert StarterContent.added?(locale: "en")
  end

  test "create_pages_and_posts! writes in the given locale" do
    StarterContent.create_pages_and_posts!(locale: "de")

    assert Mobility.with_locale(:de) { Page.i18n.where(slug: "blog").exists? }
  end

  test "running it twice creates nothing new" do
    StarterContent.create_pages_and_posts!(locale: "en")

    assert_no_difference [ "Page.count", "Post.count", "ContentBlock.count" ] do
      StarterContent.create_pages_and_posts!(locale: "en")
    end
  end

  test "added? is false before starter content exists" do
    assert_not StarterContent.added?(locale: "en")
  end

  test "running it again in another locale creates nothing new" do
    StarterContent.create_pages_and_posts!(locale: "de")

    assert_no_difference [ "Page.count", "Post.count", "ContentBlock.count" ] do
      StarterContent.create_pages_and_posts!(locale: "en")
    end
    assert StarterContent.added?(locale: "en")
  end
end
