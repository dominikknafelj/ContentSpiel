require "test_helper"

class ContentBlockTest < ActiveSupport::TestCase
  setup do
    @page = Page.create!(page_type: :standard, title: "Home", slug: "")
  end

  test "block_type is required" do
    block = ContentBlock.new(owner: @page, position: 0)

    assert_not block.valid?
  end

  test "block_type is a string checked against the BlockTypes registry" do
    assert_equal %w[rich_text image post_list], BlockTypes.names
  end

  test "a block belongs to an owner" do
    block = ContentBlock.new(block_type: :rich_text, position: 0)

    assert_not block.valid?
    assert_includes block.errors[:owner], "must exist"
  end

  test "a rich_text block accepts a rich text body" do
    block = ContentBlock.create!(owner: @page, block_type: :rich_text, position: 0, body: "<p>Hi</p>")

    assert block.body.present?
    assert_includes block.body.to_plain_text, "Hi"
  end

  # Same mobility-actiontext setup as Post#body: one ActionText::RichText row
  # per locale, not one per record.
  test "a rich_text block's body is independently translatable per locale" do
    block = ContentBlock.create!(owner: @page, block_type: :rich_text, position: 0, body: "<p>Hi</p>")
    Mobility.with_locale(:de) { block.update!(body: "<p>Hallo</p>") }

    reloaded = ContentBlock.find(block.id)

    assert_includes reloaded.body.to_plain_text, "Hi"
    Mobility.with_locale(:de) { assert_includes reloaded.body.to_plain_text, "Hallo" }
    # No Spanish body was ever written, and plain readers no longer fall back
    # to another locale (see config/initializers/mobility.rb) -- that's
    # `Locales.read`'s job now (see locales_test.rb), not the plain reader's.
    Mobility.with_locale(:es) { assert_not reloaded.body.present? }
  end

  test "an image block accepts an attached image and a caption" do
    block = ContentBlock.new(owner: @page, block_type: :image, position: 0, caption: "A photo")
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
    block = ContentBlock.create!(owner: @page, block_type: :image, position: 0, caption: "A photo")
    Mobility.with_locale(:de) { block.update!(caption: "Ein Foto") }

    reloaded = ContentBlock.find(block.id)

    assert_equal "A photo", reloaded.caption
    Mobility.with_locale(:de) { assert_equal "Ein Foto", reloaded.caption }
    # No Spanish caption was ever written, and plain readers no longer fall
    # back to another locale (see config/initializers/mobility.rb) --
    # that's `Locales.read`'s job now (see locales_test.rb), not the plain
    # reader's.
    Mobility.with_locale(:es) { assert_nil reloaded.caption }
  end

  # Proves the jsonb backend is what's storing the caption -- every locale lives
  # in one column on the content_blocks row, not in a side table.
  test "caption is stored as one jsonb column holding every locale" do
    block = ContentBlock.create!(owner: @page, block_type: :image, position: 0, caption: "A photo")
    Mobility.with_locale(:de) { block.update!(caption: "Ein Foto") }

    raw = ContentBlock.connection.select_one("SELECT caption FROM content_blocks WHERE id = #{block.id}")

    assert_equal({ "en" => "A photo", "de" => "Ein Foto" }, JSON.parse(raw["caption"]))
  end

  test "a post_list block's settings content_type must be a real registered content type" do
    block = ContentBlock.new(owner: @page, block_type: :post_list, position: 0,
      settings: { "content_type" => "not_a_real_type" })

    assert_not block.valid?
    assert block.errors["settings.content_type"].any?
  end

  test "a post_list block's settings content_type is accepted when valid" do
    block = ContentBlock.new(owner: @page, block_type: :post_list, position: 0,
      settings: { "content_type" => "blog", "limit" => 5 })

    assert block.valid?, block.errors.full_messages.inspect
  end

  # The whole of `settings` is optional: a post_list with no content_type lists
  # every type.
  test "a post_list block with no content_type setting is valid" do
    block = ContentBlock.new(owner: @page, block_type: :post_list, position: 0)

    assert block.valid?, block.errors.full_messages.inspect
  end

  # `settings` is only meaningful for post_list blocks, so a stray key on
  # another type is simply not part of its field schema and is ignored
  # (`ContentModel::FieldSet#assign` skips a key with no matching field)
  # rather than validated as if it were one.
  test "the content_type check does not apply to other block types" do
    block = ContentBlock.new(owner: @page, block_type: :rich_text, position: 0,
      settings: { "content_type" => "not_a_real_type" })

    assert block.valid?, block.errors.full_messages.inspect
  end

  # Plain structural criteria, identical in every locale -- unlike `caption`,
  # `settings` is deliberately not translated.
  test "settings are shared across locales" do
    block = ContentBlock.create!(owner: @page, block_type: :post_list, position: 0,
      settings: { "content_type" => "blog", "tag" => "ruby", "limit" => 5 })

    Mobility.with_locale(:de) do
      assert_equal({ "content_type" => "blog", "tag" => "ruby", "limit" => 5 },
        ContentBlock.find(block.id).settings)
    end
  end

  test "Page#content_blocks are ordered by position" do
    ContentBlock.create!(owner: @page, block_type: :rich_text, position: 1, body: "second")
    ContentBlock.create!(owner: @page, block_type: :rich_text, position: 0, body: "first")

    assert_equal [ 0, 1 ], @page.content_blocks.map(&:position)
    assert_equal [ "first", "second" ],
      @page.content_blocks.map { |block| block.body.to_plain_text }
  end

  test "destroying a page destroys its content blocks" do
    block = ContentBlock.create!(owner: @page, block_type: :rich_text, position: 0, body: "<p>Hi</p>")

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

  # Uses `@page` (setup's own homepage) rather than the brief's literal
  # `Page.create!(title: "Home", slug: "", ...)` -- creating a *second*
  # slug-less, parentless page collides with `@page` on both `only_one_root_page`
  # and the "/" path itself, and this test's own point (`lists?`) doesn't
  # depend on which page hosts the block.
  test "lists? matches content type and tag like listed_posts" do
    block = @page.content_blocks.create!(block_type: :post_list, position: 0, settings: { "content_type" => "blog", "tag" => " Rails " })
    post = Post.create!(content_type: :blog, title: "Hi")
    assert_not block.lists?(post)
    post.tags << Tag.create!(name: "rails")
    assert block.lists?(post.reload)
  end
end
