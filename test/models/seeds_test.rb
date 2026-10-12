require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  # find_or_create_post!/find_or_create_page! (db/seeds.rb) exist specifically
  # because a plain find_or_create_by!(title: ...) or (slug: ...) against a
  # Mobility jsonb column never finds what it just created -- silently, not
  # an error -- so re-running the seed would otherwise try to recreate every
  # Post and Page on each load and fail their own uniqueness validations.
  # Asserting zero difference on the second run is what would catch that
  # regression.
  test "seeding is idempotent and creates the demo content exactly once" do
    original_env = Rails.env

    begin
      # Mock Rails.env to return development
      development_env = ActiveSupport::StringInquirer.new("development")
      Rails.singleton_class.alias_method :_original_env, :env
      Rails.singleton_class.define_method(:env) { development_env }

      assert_difference "User.count", 1 do
        TestOutput.quietly { load Rails.root.join("db/seeds.rb") }
      end
      assert_equal 5, Page.count
      assert_equal 5, Post.count
      assert_equal 1, PostRelation.count
      # Bodies are JSON documents (design spec §5 "Writers of JSON"); the
      # demo video is a `youtube` node now, not a `YoutubeEmbed` attachment.
      assert Post.all.all? { |post| !post.body_document(locale: "en").blank? }
      assert ContentBlock.where(block_type: "rich_text").all? { |block| !block.body_document(locale: "en").blank? }
      youtube_ids = (Post.all.to_a + ContentBlock.all.to_a).flat_map do |record|
        record.body_document(locale: "en").to_h["content"].select { |node| node["type"] == "youtube" }.map { |node| node.dig("attrs", "id") }
      end
      assert_equal [ "dQw4w9WgXcQ", "dQw4w9WgXcQ" ], youtube_ids

      # The public site draws published copies: the seed publishes what it
      # built, so a seeded page has its blocks and a seeded post its body.
      site_settings(:default).update!(setup_completed_at: Time.current)
      about = Page.i18n.where(slug: "about").first
      post = Post.i18n.where(slug: "software-engineer").first
      integration = ActionDispatch::Integration::Session.new(Rails.application)
      integration.get PublicSite::Urls.new.path_for(about, :en)
      assert_includes integration.response.body, "I write about Rails, i18n"
      integration.get PublicSite::Urls.new.path_for(post, :en)
      assert_includes Nokogiri::HTML(integration.response.body).at_css("main").text, "Widgets Inc's customer-facing API"

      assert_no_difference [ "User.count", "Page.count", "Post.count", "PostRelation.count" ] do
        TestOutput.quietly { load Rails.root.join("db/seeds.rb") }
      end
    ensure
      Rails.singleton_class.remove_method :env
      Rails.singleton_class.alias_method :env, :_original_env
      Rails.singleton_class.remove_method :_original_env
    end
  end

  test "seeding does nothing outside development" do
    begin
      # Mock Rails.env to return test
      test_env = ActiveSupport::StringInquirer.new("test")
      Rails.singleton_class.alias_method :_original_env, :env
      Rails.singleton_class.define_method(:env) { test_env }

      assert_no_difference "User.count" do
        TestOutput.quietly { load Rails.root.join("db/seeds.rb") }
      end
    ensure
      Rails.singleton_class.remove_method :env
      Rails.singleton_class.alias_method :env, :_original_env
      Rails.singleton_class.remove_method :_original_env
    end
  end
end
