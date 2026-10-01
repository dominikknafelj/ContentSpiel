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

  # Starter sections and sample posts in the trash don't count as "already
  # there": the offer comes back, and adding again creates fresh ones next
  # to the trashed (whose slugs the trash freed).
  test "trashing the starter sections brings the offer back" do
    StarterContent.create_pages_and_posts!(locale: "en")
    home = Page.find_by(parent_id: nil)
    Current.set(actor: users(:one)) do
      home.children.each { |page| assert Trash::Move.call(page).ok? }
      Post.find_each { |post| assert Trash::Move.call(post).ok? }
    end

    assert_not StarterContent.added?(locale: "en")
    assert_difference -> { Page.kept.count } => 3, -> { Post.kept.count } => 3 do
      assert StarterContent.add_once!(locale: "en")
    end
    assert StarterContent.added?(locale: "en")
  end

  test "running it again in another locale creates nothing new" do
    StarterContent.create_pages_and_posts!(locale: "de")

    assert_no_difference [ "Page.count", "Post.count", "ContentBlock.count" ] do
      StarterContent.create_pages_and_posts!(locale: "en")
    end
    assert StarterContent.added?(locale: "en")
  end

  # Final fix wave (C, P23): the one path both the setup wizard and CS
  # Studio's "Create starter pages" take -- under the `SiteSetting` row
  # lock, re-checking `added?` inside it, with any write failure rolled
  # back and raised as `StarterContent::Error`.
  test "add_once! creates the starter content once, under the site settings lock" do
    statements = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, payload| statements << payload[:sql] }
    begin
      assert StarterContent.add_once!(locale: "en")
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
    assert statements.any? { |sql| sql.include?(%(FROM "site_settings")) && sql.include?("FOR UPDATE") }

    assert_no_difference [ "Page.count", "Post.count" ] do
      assert_not StarterContent.add_once!(locale: "en")
    end
  end

  test "add_once! rolls back and raises StarterContent::Error when a write fails" do
    home = root_page
    failing = ->(**) {
      Pages::Save.call(attributes: { parent: home, published: true }, translations: { "en" => { title: "Half built" } })
      raise ActiveRecord::RecordNotUnique, "duplicate slug"
    }

    with_singleton_override(StarterContent, :create_pages_and_posts!, failing) do
      assert_no_difference [ "Page.count", "Post.count" ] do
        assert_raises(StarterContent::Error) { StarterContent.add_once!(locale: "en") }
      end
    end
  end
end
