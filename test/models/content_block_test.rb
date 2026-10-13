require "test_helper"

class ContentBlockTest < ActiveSupport::TestCase
  include TestTypes

  setup do
    @page = Page.create!(page_type: :standard, title: "Home", slug: "")
  end

  test "block_type is required" do
    block = ContentBlock.new(owner: @page, position: 0)

    assert_not block.valid?
  end

  # `block_type_is_registered` used to run unconditionally, so a blank
  # `block_type` failed it too -- reporting "isn't a registered block type"
  # on top of `presence`'s own "can't be blank", the same double-error
  # `Post#content_type_is_registered` guards against with its own
  # `content_type.present? &&` check. This mirrors that guard.
  test "a blank block_type gets only the presence error, not also 'isn't registered'" do
    block = ContentBlock.new(owner: @page, position: 0, block_type: "")

    assert_not block.valid?
    assert_equal [ "can't be blank" ], block.errors[:block_type]
  end

  test "block_type is a string checked against the BlockTypes registry" do
    assert_equal %w[rich_text image code post_list section], BlockTypes.names
  end

  test "a block belongs to an owner" do
    block = ContentBlock.new(block_type: :rich_text, position: 0)

    assert_not block.valid?
    assert_includes block.errors[:owner], "must exist"
  end

  test "a rich_text block stores a JSON body document" do
    block = ContentBlock.create!(owner: @page, block_type: :rich_text, position: 0, body: rich_doc("Hi"))

    assert_equal rich_doc("Hi"), block.reload.body_document(locale: Locales.default).to_h
  end

  # Same per-locale jsonb shape as Post#body: one document per locale.
  test "a rich_text block's body is independently translatable per locale" do
    block = ContentBlock.create!(owner: @page, block_type: :rich_text, position: 0, body: rich_doc("Hi"))
    block.assign_body(rich_doc("Hallo"), locale: "de")
    block.save!

    reloaded = ContentBlock.find(block.id)

    assert_equal rich_doc("Hi"), reloaded.body_document(locale: "en").to_h
    assert_equal rich_doc("Hallo"), reloaded.body_document(locale: "de").to_h
    # No Spanish body was ever written, and `body_document` reads the literal
    # locale -- falling back is `Locales.read`'s job (see locales_test.rb).
    assert reloaded.body_document(locale: "es").blank?
  end

  test "an invalid body document is a validation error on body" do
    block = ContentBlock.new(owner: @page, block_type: :rich_text, position: 0)
    block.assign_body({ "type" => "doc", "content" => [ { "type" => "nope/unknown" } ] }, locale: "en")

    assert_not block.save
    assert block.errors[:body].any?
  end

  # Media library Task 4: the image is a reference to a library asset.
  test "an image block references a library image and keeps its own caption" do
    asset = create_media_asset
    block = ContentBlock.create!(owner: @page, block_type: :image, position: 0, caption: "A photo", media_asset: asset)

    reloaded = ContentBlock.find(block.id)

    assert_equal asset, reloaded.media_asset
    assert_equal "A photo", reloaded.caption
    assert_not reloaded.respond_to?(:image)
  end

  test "an image block can be saved before its image is chosen" do
    assert ContentBlock.new(owner: @page, block_type: :image, position: 0).valid?
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

  # `normalize_settings` re-derives `settings` from the raw hash every nested
  # form submission writes it as (see the comment on `ContentBlock
  # #normalize_settings`) -- but it used to do that through
  # `untranslated_hash` alone, which *drops* a translated field found in that
  # raw hash instead of routing it to `translated_settings`, since nothing
  # ever wrote `translated_settings` from the raw path. A test-only block
  # type with a translated setting (open-types spec §8's "open-type proof")
  # is what exercises this, since none of the built-ins have one.
  test "normalize_settings moves a translated key found in raw settings into translated_settings, in the default locale" do
    saved = BlockTypes.all.dup
    BlockTypes.register(:test_translated) { |t| t.label "Test translated"; t.field :headline, :string, translated: true }

    block = ContentBlock.new(owner: @page, block_type: :test_translated, position: 0,
      settings: { "headline" => "Hello" })

    assert block.valid?, block.errors.full_messages.inspect
    assert_equal({}, block.settings)
    assert_equal({ Locales.default => { "headline" => "Hello" } }, block.translated_settings)
  ensure
    BlockTypes.reset!
    saved.each { |definition| BlockTypes.registry_put(definition) }
  end

  test "Page#content_blocks are ordered by position" do
    ContentBlock.create!(owner: @page, block_type: :rich_text, position: 1, body: rich_doc("second"))
    ContentBlock.create!(owner: @page, block_type: :rich_text, position: 0, body: rich_doc("first"))

    assert_equal [ 0, 1 ], @page.content_blocks.map(&:position)
    assert_equal [ "first\n", "second\n" ],
      @page.content_blocks.map { |block| block.body_document(locale: "en").to_markdown }
  end

  test "destroying a page destroys its content blocks" do
    block = ContentBlock.create!(owner: @page, block_type: :rich_text, position: 0, body: rich_doc("Hi"))

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

  # A post's content_type can go stale the same way a block's block_type can
  # (a removed plugin, a typo fixed by hand in the database) -- spec §4.2
  # says such a post "has no public URL", which only holds if an unfiltered
  # ("every content type") listing skips it too; otherwise it shows up
  # linked to a path that was never computed for it (see
  # `PublicSite::Paths.compute_path`, which likewise skips a post whose `definition`
  # is nil).
  test "an unfiltered post list omits a post whose content_type isn't registered" do
    @page.update!(published_at: Time.current)
    known = Post.create!(content_type: :blog, title: "Known", published_at: 1.day.ago)
    orphan = Post.create!(content_type: :blog, title: "Orphan", published_at: 1.day.ago)
    orphan.update_column(:content_type, "gone/thing")
    block = @page.content_blocks.create!(block_type: :post_list, position: 0)

    assert_equal [ known ], block.listed_posts.to_a
  end

  test "lists? is false for a post whose content_type isn't registered" do
    block = @page.content_blocks.create!(block_type: :post_list, position: 0)
    post = Post.create!(content_type: :blog, title: "Hi")
    post.update_column(:content_type, "gone/thing")

    assert_not block.lists?(post)
  end

  # A required translated setting is only ever written at `Locales.default`
  # (`normalize_settings`'s own comment explains why: neither the standalone
  # block form nor the page form's nested rows have a locale switcher for
  # `settings` yet). Checking `required` against the *ambient* `I18n.locale`
  # instead -- whatever a request happened to leave it at, unrelated to the
  # site's own default -- would reject a block that saved correctly the
  # moment that ambient locale doesn't match the site's default.
  test "settings_are_valid checks a required translated field at the site's default locale, not the ambient one" do
    with_locales(%w[de en], default: "de")

    with_test_types do
      block = @page.content_blocks.build(block_type: "test/quote", position: 0)
      block.assign_settings({ "text" => "Hallo" }, locale: "de")

      assert block.valid?, block.errors.full_messages.to_sentence
    end
  end

  test "a typed setting's error names its field in words, never the dotted path" do
    block = ContentBlock.new(owner: @page, block_type: "post_list", position: 0, settings: { "limit" => 0 })

    assert_not block.valid?
    assert_includes block.errors.full_messages, "Limit must be greater than or equal to 1"
    assert_equal "Limit", ContentBlock.human_attribute_name("settings.limit")
    assert_equal "Block type", ContentBlock.human_attribute_name("block_type")
  end

  # Design answer C5: a message names the field as its input does.
  test "a typed setting's error names its field by the field's own label where its type gives one" do
    block = ContentBlock.new(owner: @page, block_type: "code", position: 0, settings: { "code" => "x" * (CodeHighlight::MAX_CHARACTERS + 1) })
    block.valid?
    block.errors.add("settings.filename", :invalid)

    assert_includes block.errors.full_messages, "File name is invalid"
    assert_equal "File name", ContentBlock.human_attribute_name("settings.filename", base: block)
    assert_equal "Filename", ContentBlock.human_attribute_name("settings.filename"), "asked without the block, the name humanised"
    assert_equal "Code", ContentBlock.human_attribute_name("settings.code", base: block)
    gone = ContentBlock.new(owner: @page, block_type: "gone/type", position: 0)
    assert_equal "Filename", ContentBlock.human_attribute_name("settings.filename", base: gone)
  end

  def section_on(page, layout: "two", position: 0)
    page.content_blocks.create!(block_type: "section", position: position, settings: { "layout" => layout })
  end

  test "a section's settings default to two columns, no background, content width" do
    section = section_on(create_page(title: "Defaults"), layout: nil)

    assert_equal %w[two none content], section.settings_object.then { |s| [ s.layout, s.background, s.width ] }
    assert_predicate section, :container?
    assert_equal 2, section.column_count
  end

  test "column_count follows the layout, and is 0 for a block that holds nothing" do
    page = create_page(title: "Counts")
    counts = %w[one two three four one_two two_one].map { |layout| section_on(page, layout: layout).column_count }

    assert_equal [ 1, 2, 3, 4, 2, 2 ], counts
    assert_equal 0, page.content_blocks.create!(block_type: "rich_text", position: 9).column_count
  end

  test "a block in a section needs a column of that section's layout" do
    page = create_page(title: "Columns")
    section = section_on(page, layout: "two")

    assert page.content_blocks.build(block_type: "rich_text", section: section, section_column: 2).valid?
    assert_not page.content_blocks.build(block_type: "rich_text", section: section, section_column: 3).valid?
    assert_not page.content_blocks.build(block_type: "rich_text", section: section, section_column: nil).valid?
    assert_not page.content_blocks.build(block_type: "rich_text", section_column: 1).valid?
  end

  test "a section never sits in a section" do
    page = create_page(title: "Nesting")
    outer = section_on(page)
    inner = page.content_blocks.build(block_type: "section", section: outer, section_column: 1)

    assert_not inner.valid?
    assert_includes inner.errors[:section], "can't hold another section"
  end

  test "a block's section is a section of the same page" do
    page = create_page(title: "Here")
    elsewhere = section_on(create_page(title: "There"))
    text = page.content_blocks.create!(block_type: "rich_text", position: 0)

    assert_not page.content_blocks.build(block_type: "rich_text", section: elsewhere, section_column: 1).valid?
    assert_not page.content_blocks.build(block_type: "rich_text", section: text, section_column: 1).valid?
  end

  test "the database keeps section and column together and refuses to delete a section that holds a block" do
    page = create_page(title: "Database")
    section = section_on(page)
    inside = page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 1, position: 0)

    assert_raises(ActiveRecord::StatementInvalid) { ContentBlock.transaction(requires_new: true) { inside.update_columns(section_column: nil) } }
    assert_raises(ActiveRecord::InvalidForeignKey) { ContentBlock.transaction(requires_new: true) { section.destroy } }
  end

  test "a block in a section whose type is gone still saves" do
    page = create_page(title: "Dormant")
    section = section_on(page)
    inside = page.content_blocks.create!(block_type: "image", section: section, section_column: 1, position: 0)
    section.update_columns(block_type: "gone/section")

    assert inside.reload.update(caption: "Still editable")
  end

  test "top_level and in_column narrow a page's blocks" do
    page = create_page(title: "Scopes")
    text = page.content_blocks.create!(block_type: "rich_text", position: 0)
    section = section_on(page, position: 1)
    first = page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 1, position: 0)
    second = page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 2, position: 0)

    assert_equal [ text, section ], page.content_blocks.top_level.to_a
    assert_equal [ second ], page.content_blocks.in_column(section, 2).to_a
    assert_equal [ first, second ], section.section_blocks.to_a
  end

  test "destroying a page destroys the blocks in its sections first" do
    page = create_page(title: "Doomed")
    section = section_on(page)
    page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 1, position: 0)

    assert_difference -> { ContentBlock.count }, -2 do
      page.reload.destroy!
    end
  end
end
