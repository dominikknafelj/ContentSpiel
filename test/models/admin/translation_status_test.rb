require "test_helper"

class Admin::TranslationStatusTest < ActiveSupport::TestCase
  include TestTypes

  test "a page's missing locale is one whose title is blank" do
    with_locales(%w[de en], default: "de") do
      page = create_page(title: "Über uns")
      assert_equal %w[en], Admin::TranslationStatus.missing_locales(page)
    end
  end

  test "a page is complete once every enabled locale's title is filled in" do
    with_locales(%w[de en], default: "de") do
      page = create_page(title: "Über uns", translations: { "en" => { title: "About" } })
      assert_empty Admin::TranslationStatus.missing_locales(page)
    end
  end

  test "a block's required translated setting left blank in a locale marks that locale missing, even with the title filled in" do
    with_locales(%w[de en], default: "de") do
      with_test_types do
        page = create_page(title: "Über uns", translations: { "en" => { title: "About" } })
        result = ContentBlocks::Save.call(page.content_blocks.new, attributes: { block_type: "test/quote", settings: { text: "Hallo" } })
        assert result.ok?, result.errors.to_sentence

        assert_equal %w[en], Admin::TranslationStatus.missing_locales(page)
      end
    end
  end

  test "a block's non-required field never marks a locale missing" do
    with_locales(%w[de en], default: "de") do
      with_test_types do
        page = create_page(title: "Über uns", translations: { "en" => { title: "About" } })
        result = ContentBlocks::Save.call(page.content_blocks.new, attributes: { block_type: "test/quote", settings: { text: "Hallo" } },
          translations: { "en" => { settings: { text: "Hello" } } })
        assert result.ok?, result.errors.to_sentence

        assert_empty Admin::TranslationStatus.missing_locales(page)
      end
    end
  end

  test "an unavailable block type is never treated as missing" do
    with_locales(%w[de en], default: "de") do
      page = create_page(title: "Über uns", translations: { "en" => { title: "About" } })
      block = page.content_blocks.create!(block_type: "rich_text", position: 0)
      block.update_column(:block_type, "plugins/removed") # bypasses block_type_is_registered, same as the post-side test below

      assert_empty Admin::TranslationStatus.missing_locales(page)
    end
  end

  test "a post's missing locale is one whose title is blank" do
    with_locales(%w[de en], default: "de") do
      post = create_post(title: "Start")
      assert_equal %w[en], Admin::TranslationStatus.missing_locales(post)
    end
  end

  test "a post is complete once every enabled locale's title is filled in" do
    with_locales(%w[de en], default: "de") do
      post = Posts::Save.call(Post.new, attributes: { content_type: "blog" },
        translations: { "de" => { title: "Start" }, "en" => { title: "Launch" } }).record

      assert_empty Admin::TranslationStatus.missing_locales(post)
    end
  end

  # None of the built-in content types (nor `test/event`, the one
  # `with_test_types` registers) have a required *translated* schema field --
  # this registers its own throwaway one, restored in `ensure` the same way
  # `Post#fields_are_valid checks a required translated field...` (test/
  # models/post_test.rb) already does, so this test doesn't have to lean on
  # `with_test_types`'s own fixed shape for something it doesn't offer.
  test "a post's required translated schema field left blank in a locale marks that locale missing, even with the title filled in" do
    with_locales(%w[de en], default: "de") do
      saved = ContentTypes.all.dup
      begin
        ContentTypes.register("test/interview") { |t| t.label "Interview"; t.field :quote, :string, required: true, translated: true }

        post = Posts::Save.call(Post.new, attributes: { content_type: "test/interview", fields: { quote: "Hallo" } },
          translations: { "de" => { title: "Start" }, "en" => { title: "Launch" } }).record

        assert_equal %w[en], Admin::TranslationStatus.missing_locales(post)
      ensure
        ContentTypes.reset!
        saved.each { |definition| ContentTypes.registry_put(definition) }
      end
    end
  end

  test "an unregistered content type is never treated as missing" do
    with_locales(%w[de en], default: "de") do
      post = Posts::Save.call(Post.new, attributes: { content_type: "blog" },
        translations: { "de" => { title: "Start" }, "en" => { title: "Launch" } }).record
      post.update_column(:content_type, "plugins/removed")

      assert_empty Admin::TranslationStatus.missing_locales(post)
    end
  end
end
