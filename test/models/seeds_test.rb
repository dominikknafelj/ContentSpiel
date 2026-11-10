require "test_helper"
require_relative "../support/schema_loaded_database"
require_relative "../support/service_calls"

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
      # The homepage, four pages of the demo, and the showcase with its seven.
      assert_equal 13, Page.count
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

      assert_no_difference [ "User.count", "Page.count", "Post.count", "PostRelation.count", "ContentBlock.count" ] do
        TestOutput.quietly { load Rails.root.join("db/seeds.rb") }
      end
    ensure
      Rails.singleton_class.remove_method :env
      Rails.singleton_class.alias_method :env, :_original_env
      Rails.singleton_class.remove_method :_original_env
    end
  end

  # The showcase (db/seeds/showcase.rb) run on its own, on the suite's site
  # with its three languages: what each page holds, every page drawn once
  # published, and nothing written the second time.
  test "the showcase draws every type at the top level and in every layout and band, every note kind, a long table, every list and a 404 link, and writes nothing the second time" do
    require Rails.root.join("db/seeds/showcase").to_s
    showcase = DevelopmentShowcase.call(root: root_page, image: create_media_asset)
    pages = Page.where(parent: showcase).index_by(&:slug)
    content = BlockTypes.all.reject { |definition| definition.capability?(:container) }.map(&:name).sort
    layouts = BlockTypes::Section::LAYOUTS.keys

    assert_equal content, pages.fetch("every-block").content_blocks.where(section_id: nil).pluck(:block_type).sort

    BlockTypes::Section::BACKGROUNDS.each do |background|
      sections = pages.fetch("band-#{background}").content_blocks.where(block_type: "section", section_id: nil).to_a
      assert_equal layouts + [ "three" ], sections.map { |section| section.settings["layout"] }, background
      assert_equal [ background ], sections.map { |section| section.settings["background"] }.uniq
      assert_equal [ "content" ] * layouts.size + [ "full" ], sections.map { |section| section.settings["width"] }
      sections.each do |section|
        assert_equal content, section.section_blocks.pluck(:block_type).sort, "#{background} #{section.settings["layout"]}"
        assert_equal (1..section.column_count).to_a, section.section_blocks.pluck(:section_column).uniq.sort, "every column of a #{section.settings["layout"]} section holds a block"
      end
    end

    notes = pages.fetch("every-note").content_blocks
    kinds = BlockTypes::Note::KINDS.keys
    assert_equal kinds.flat_map { |kind| [ kind, kind ] }, notes.where(block_type: "note", section_id: nil).map { |note| note.settings["kind"] }
    assert_includes notes.where(block_type: "note", section_id: nil).map { |note| note.settings["title"].to_s }, ""
    %w[tinted strong].each do |background|
      band = notes.find { |block| block.settings["background"] == background }
      assert_equal kinds.sort, band.section_blocks.map { |note| note.settings["kind"] }.sort, "every kind in a #{background} band"
    end

    table = pages.fetch("a-long-table").content_blocks.sole
    rows = table.body_document(locale: "en").to_h["content"].find { |node| node["type"] == "table" }["content"]
    assert_operator rows.size, :>, 30

    lists = pages.fetch("every-list").content_blocks.map { |block| block.settings.slice("content_type", "tag").compact }
    assert_equal ContentTypes.names.map { |type| { "content_type" => type.to_s } } + [ { "tag" => "ruby" } ], lists

    links = showcase.content_blocks.sole.body_document(locale: "en").to_h.to_s
    assert_includes links, "/showcase/no-such-page"

    [ showcase, *pages.values ].each { |page| publish_changes(page) }
    integration = ActionDispatch::Integration::Session.new(Rails.application)
    [ showcase, *pages.values ].each do |page|
      integration.get PublicSite::Urls.new.path_for(page, :en)
      assert_equal 200, integration.response.status, page.slug
    end
    integration.get "/showcase/no-such-page"
    assert_equal 404, integration.response.status

    assert_no_difference [ "Page.count", "ContentBlock.count", "Forms::Form.count" ] do
      DevelopmentShowcase.call(root: root_page, image: create_media_asset)
    end
  end

  # A first production start: `db:prepare` loads the schema, which holds no
  # rows, and then this file. What every environment needs is above the line
  # that ends it outside development (`Groups::EnsureBuiltIns`).
  test "outside development the seed makes the built-in groups of a schema-loaded database, no account and no content, and nothing the second time" do
    extend SchemaLoadedDatabase
    empty_as_after_a_schema_load

    begin
      production_env = ActiveSupport::StringInquirer.new("production")
      Rails.singleton_class.alias_method :_original_env, :env
      Rails.singleton_class.define_method(:env) { production_env }

      assert_no_difference [ "User.count", "Page.count", "Post.count", "SiteSetting.count" ] do
        TestOutput.quietly { load Rails.root.join("db/seeds.rb") }
      end
      assert_equal [ "Admin", "Author", "Editor", "Read only" ], AccessControl::Group.where(built_in: true).order(:name).pluck(:name)
      assert_equal AccessControl::Permissions.grantable.map(&:key).sort, AccessControl::Group.find_by!(name: "Admin").grants.pluck(:permission).sort

      before = ServiceCalls.digests(except: [])
      TestOutput.quietly { load Rails.root.join("db/seeds.rb") }
      assert_equal before, ServiceCalls.digests(except: []), "a second run of the seed wrote something"
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
