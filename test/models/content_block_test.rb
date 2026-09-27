require "test_helper"

class ContentBlockTest < ActiveSupport::TestCase
  setup do
    @page = Page.create!(page_type: :standard, title: "Home", slug: "")
  end

  test "block_type is required" do
    block = ContentBlock.new(page: @page, position: 0)

    assert_not block.valid?
  end

  test "block_type is an enum with rich_text, image and post_list" do
    assert_equal %w[rich_text image post_list], ContentBlock.block_types.keys
  end

  test "a block belongs to a page" do
    block = ContentBlock.new(block_type: :rich_text, position: 0)

    assert_not block.valid?
    assert_includes block.errors[:page], "must exist"
  end

  test "a rich_text block accepts a rich text body" do
    block = ContentBlock.create!(page: @page, block_type: :rich_text, position: 0, body: "<p>Hi</p>")

    assert block.body.present?
    assert_includes block.body.to_plain_text, "Hi"
  end

  # Same mobility-actiontext setup as Post#body: one ActionText::RichText row
  # per locale, not one per record.
  test "a rich_text block's body is independently translatable per locale" do
    block = ContentBlock.create!(page: @page, block_type: :rich_text, position: 0, body: "<p>Hi</p>")
    Mobility.with_locale(:de) { block.update!(body: "<p>Hallo</p>") }

    reloaded = ContentBlock.find(block.id)

    assert_includes reloaded.body.to_plain_text, "Hi"
    Mobility.with_locale(:de) { assert_includes reloaded.body.to_plain_text, "Hallo" }
    # No Spanish body was ever written, so this is the English fallback.
    Mobility.with_locale(:es) { assert_includes reloaded.body.to_plain_text, "Hi" }
  end

  test "an image block accepts an attached image and a caption" do
    block = ContentBlock.new(page: @page, block_type: :image, position: 0, caption: "A photo")
    block.image.attach(
      io: StringIO.new("fake image data"),
      filename: "photo.jpg",
      content_type: "image/jpeg"
    )
    block.save!

    reloaded = ContentBlock.find(block.id)

    assert reloaded.image.attached?
    assert_equal "photo.jpg", reloaded.image.filename.to_s
    assert_equal "fake image data", reloaded.image.download
    assert_equal "A photo", reloaded.caption
  end

  test "caption is independently translatable per locale" do
    block = ContentBlock.create!(page: @page, block_type: :image, position: 0, caption: "A photo")
    Mobility.with_locale(:de) { block.update!(caption: "Ein Foto") }

    reloaded = ContentBlock.find(block.id)

    assert_equal "A photo", reloaded.caption
    Mobility.with_locale(:de) { assert_equal "Ein Foto", reloaded.caption }
    # No Spanish caption was ever written, so this is the English fallback.
    Mobility.with_locale(:es) { assert_equal "A photo", reloaded.caption }
  end

  # Proves the jsonb backend is what's storing the caption -- every locale lives
  # in one column on the content_blocks row, not in a side table.
  test "caption is stored as one jsonb column holding every locale" do
    block = ContentBlock.create!(page: @page, block_type: :image, position: 0, caption: "A photo")
    Mobility.with_locale(:de) { block.update!(caption: "Ein Foto") }

    raw = ContentBlock.connection.select_one("SELECT caption FROM content_blocks WHERE id = #{block.id}")

    assert_equal({ "en" => "A photo", "de" => "Ein Foto" }, JSON.parse(raw["caption"]))
  end

  test "a post_list block's settings content_type must be a real Post content_type" do
    block = ContentBlock.new(page: @page, block_type: :post_list, position: 0,
      settings: { "content_type" => "not_a_real_type" })

    assert_not block.valid?
    assert_includes block.errors[:settings],
      "content_type must be one of: #{Post.content_types.keys.join(', ')}"
  end

  test "a post_list block's settings content_type is accepted when valid" do
    block = ContentBlock.new(page: @page, block_type: :post_list, position: 0,
      settings: { "content_type" => "blog", "limit" => 5 })

    assert block.valid?, block.errors.full_messages.inspect
  end

  # The whole of `settings` is optional: a post_list with no content_type lists
  # every type.
  test "a post_list block with no content_type setting is valid" do
    block = ContentBlock.new(page: @page, block_type: :post_list, position: 0)

    assert block.valid?, block.errors.full_messages.inspect
  end

  # `settings` is only meaningful for post_list blocks, so a stray key on
  # another type must not be validated as if it were one.
  test "the content_type check does not apply to other block types" do
    block = ContentBlock.new(page: @page, block_type: :rich_text, position: 0,
      settings: { "content_type" => "not_a_real_type" })

    assert block.valid?, block.errors.full_messages.inspect
  end

  # Plain structural criteria, identical in every locale -- unlike `caption`,
  # `settings` is deliberately not translated.
  test "settings are shared across locales" do
    block = ContentBlock.create!(page: @page, block_type: :post_list, position: 0,
      settings: { "content_type" => "blog", "tag" => "ruby", "limit" => 5 })

    Mobility.with_locale(:de) do
      assert_equal({ "content_type" => "blog", "tag" => "ruby", "limit" => 5 },
        ContentBlock.find(block.id).settings)
    end
  end

  test "Page#content_blocks are ordered by position" do
    ContentBlock.create!(page: @page, block_type: :rich_text, position: 1, body: "second")
    ContentBlock.create!(page: @page, block_type: :rich_text, position: 0, body: "first")

    assert_equal [ 0, 1 ], @page.content_blocks.map(&:position)
    assert_equal [ "first", "second" ],
      @page.content_blocks.map { |block| block.body.to_plain_text }
  end

  test "destroying a page destroys its content blocks" do
    block = ContentBlock.create!(page: @page, block_type: :rich_text, position: 0, body: "<p>Hi</p>")

    assert @page.destroy
    assert_not ContentBlock.exists?(block.id)
  end

  test "a post list filtered by tag lists only posts with that tag, ignoring case" do
    @page.update!(published_at: Time.current)
    rails = Tag.create!(name: "rails")
    tagged = Post.create!(content_type: :blog, title: "Tagged", published_at: 1.day.ago)
    tagged.tags << rails
    Post.create!(content_type: :blog, title: "Untagged", published_at: 1.day.ago)
    block = @page.content_blocks.create!(block_type: :post_list, position: 0, settings: { "tag" => "Rails" })

    assert_equal [ tagged ], block.listed_posts.to_a
  end

  test "a post list filtered by tag with surrounding whitespace lists the post" do
    @page.update!(published_at: Time.current)
    rails = Tag.create!(name: "rails")
    tagged = Post.create!(content_type: :blog, title: "Tagged", published_at: 1.day.ago)
    tagged.tags << rails
    block = @page.content_blocks.create!(block_type: :post_list, position: 0, settings: { "tag" => "  Rails " })

    assert_equal [ tagged ], block.listed_posts.to_a
  end

  test "a post list filtered by a tag name matching no tag lists nothing" do
    @page.update!(published_at: Time.current)
    Tag.create!(name: "rails")
    Post.create!(content_type: :blog, title: "Post", published_at: 1.day.ago)
    block = @page.content_blocks.create!(block_type: :post_list, position: 0, settings: { "tag" => "nonexistent" })

    assert_equal [], block.listed_posts.to_a
  end
end
