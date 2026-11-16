require "test_helper"

# What comes back and how is `Publishing::ReturnTo`'s, pinned case by case
# in `discard_changes_test.rb`; here, what a restore adds and leaves alone:
# any version, never a publication, the pending copy untouched, the mark as
# the save services leave it, the dialog's record, its event and its rights.
# The refusal under someone else's hold is the controller's.
class Publishing::RestoreVersionTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing", published: false)
    @first = add("First")
    @section = add(nil, block_type: "section", settings: { "layout" => "three" })
    @left = add("Left", section_id: @section.id, section_column: 1)
    @middle = add("Middle", section_id: @section.id, section_column: 2)
    @right = add("Right", section_id: @section.id, section_column: 3)
    @last = add("Last")
    assert Pages::Save.call(@page, attributes: { published: true }, translations: { "de" => { title: "Preise" } }).ok?
    @version_one = shape
  end

  def add(text, **attributes)
    result = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" }.merge(attributes),
      translations: (text ? { "en" => { body: rich_doc(text) } } : {}))
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  # The page as a visitor would be shown it, without ids (as in
  # `discard_changes_test.rb`).
  def shape
    data = Publishing::Snapshot.of(@page.reload)
    sections = data["blocks"].select { |block| block["block_type"] == "section" }.map { |block| block["id"] }
    [ data["fields"].except(*Publishable::BOOKKEEPING), data["blocks"].map do |block|
      [ block["block_type"], sections.index(block["section_id"]), block["section_column"], block["settings"], block["translated_settings"],
        block["body"].to_h.reject { |_locale, document| document["content"].blank? }, block["caption"], block["alt"], block["media_asset_id"] ]
    end ]
  end

  def title(record) = Mobility.with_locale(:en) { record.reload.title }

  def restore(record, number, **options)
    result = Publishing::RestoreVersion.call(record.reload, number: number, **options)
    assert result.ok?, result.errors.to_sentence
    result
  end

  # Version 2 of the page: its title typed and published.
  def publish_two(title = "Two")
    assert Pages::Save.call(@page, translations: { "en" => { title: title } }).ok?
    publish_changes(@page)
  end

  test "restoring an older version writes its content into the rows and publishes nothing" do
    publish_two
    content_version = PublicSite.content_version
    copies = Publishing::Version.count
    published_at = @page.reload.published_at

    result = restore(@page, 1)

    assert_equal "Pricing", title(@page)
    assert_equal @version_one, shape
    assert_equal 2, Publishing.current(@page).number, "the site keeps showing version 2"
    assert @page.unpublished_changes_at.present?
    assert_equal content_version, PublicSite.content_version
    assert_equal copies, Publishing::Version.count, "a restore takes no copy"
    assert_equal published_at, @page.published_at
    assert_equal({ number: 1, images_missing: 0, tags_missing: 0, pending_at: nil }, result.value)
    assert_nil result.notice
  end

  test "restoring the newest version clears the mark, restoring an older one sets it" do
    publish_two
    assert Pages::Save.call(@page, translations: { "en" => { title: "Typed" } }).ok?
    assert @page.reload.unpublished_changes?

    restore(@page, 2)

    assert_equal "Two", title(@page)
    assert_nil @page.unpublished_changes_at, "the rows are the newest copy again"

    restore(@page, 1)

    assert @page.reload.unpublished_changes?
  end

  # Translation bookkeeping is not copied back from the version: it is what
  # the save services leave when the text is written back (spec §11).
  test "where the original's text goes back, a translation confirmed for the later text reads outdated" do
    publish_two
    assert Translations::Confirm.call(@page.reload, field: "title", locale: "de").ok?
    assert_equal :current, @page.reload.translation_state("title", "de")
    changed_at = @page.translation_original_changed_at["title"]

    travel(1.minute) { restore(@page, 1) }

    assert_equal "Pricing", title(@page)
    assert_equal "Preise", Mobility.with_locale(:de) { @page.title }, "the translation's own text is the same in both versions"
    assert_equal :outdated, @page.translation_state("title", "de")
    assert_not_equal changed_at, @page.translation_original_changed_at["title"], "the time is the services', not the version's"
  end

  test "a block deleted since comes back as a new block, one added since goes" do
    assert ContentBlocks::Destroy.call(@first).ok?
    added = add("Added")
    publish_changes(@page)

    restore(@page, 1)

    assert_equal @version_one, shape
    assert_not ContentBlock.exists?(@first.id), "the deleted block comes back under a new id"
    assert_not ContentBlock.exists?(added.id)
  end

  test "sections and their columns come back in the version's order" do
    assert ContentBlocks::Save.call(@section, attributes: { settings: { "layout" => "one" } }).ok?
    other = add(nil, block_type: "section", settings: { "layout" => "two" })
    assert ContentBlocks::Reorder.call(@page, [ @last.id ], section: other.id, column: 1, moved_from: { @last.id => { section_id: nil, column: nil } }).ok?
    assert ContentBlocks::Reorder.call(@page, [ @section.id, @first.id, other.id ]).ok?
    publish_changes(@page)

    restore(@page, 1)

    assert_equal @version_one, shape
    assert_equal [ [ @left.id, 1 ], [ @middle.id, 2 ], [ @right.id, 3 ] ],
      @section.section_blocks.reorder(:section_column, :position).pluck(:id, :section_column)
    assert_not ContentBlock.exists?(other.id)
  end

  test "a scheduled change stays scheduled" do
    assert Pages::Save.call(@page, translations: { "en" => { title: "Later" } }).ok?
    publish_changes(@page, at: 2.days.from_now)
    pending = Publishing.pending(@page)

    result = restore(@page, 1)

    assert_equal "Pricing", title(@page)
    assert_equal pending, Publishing.pending(@page)
    assert_equal pending.live_at, result.value[:pending_at]
    assert_equal 1, Publishing.current(@page).number
  end

  test "a draft with copies is restored with no mark" do
    publish_two
    assert Pages::Save.call(@page, attributes: { published: false }).ok?
    assert Pages::Save.call(@page, translations: { "en" => { title: "Typed" } }).ok?

    restore(@page, 1)

    assert_equal "Pricing", title(@page)
    assert_nil @page.unpublished_changes_at
    assert_nil @page.published_at
  end

  test "a post's tags come back by id, a deleted tag is counted and not made" do
    post = Posts::Save.call(attributes: { content_type: "blog", published: true, tag_names: %w[alpha gamma] },
      translations: { "en" => { title: "Hello", body: rich_doc("Body") } }).record
    assert Posts::Save.call(post, attributes: { tag_names: %w[other] }, translations: { "en" => { title: "Typed" } }).ok?
    publish_changes(post)
    assert Tags::Destroy.call(Tag.find_by!(name: "alpha")).ok?
    tags = Tag.count

    result = restore(post, 1)

    assert_equal %w[gamma], post.reload.tags.pluck(:name)
    assert_equal "Hello", title(post)
    assert_equal 1, result.value[:tags_missing]
    assert_equal tags, Tag.count
    assert_equal Publishing::ReturnTo::REMAINS, result.notice
    event = Audit::Event.where(action: "post.version_restored", subject: post).sole
    assert_equal({ "number" => 1, "tags_missing" => 1 }, event.metadata)
  end

  test "an image gone since is left empty, counted and said" do
    asset = create_media_asset
    image = add(nil, block_type: "image", media_asset_id: asset.id)
    publish_changes(@page)
    assert ContentBlocks::Save.call(image, attributes: { media_asset_id: nil }).ok?
    publish_changes(@page)
    assert ContentBlocks::Save.call(@first.reload, translations: { "en" => { body: rich_doc("Typed") } }).ok?
    asset.update_columns(trashed_at: Time.current) # version: none (a test trashes an image an older version shows)

    result = restore(@page, 2)

    assert_nil image.reload.media_asset_id
    assert_equal 1, result.value[:images_missing]
    assert_equal Publishing::ReturnTo::IMAGES_GONE, result.notice
    assert_equal({ "number" => 2, "images_missing" => 1 }, Audit::Event.where(action: "page.version_restored").sole.metadata)
  end

  test "a version that differs only by an image gone since has nothing to restore" do
    asset = create_media_asset
    image = add(nil, block_type: "image", media_asset_id: asset.id)
    publish_changes(@page)
    assert ContentBlocks::Save.call(image, attributes: { media_asset_id: nil }).ok?
    publish_changes(@page)
    asset.update_columns(trashed_at: Time.current) # version: none (a test trashes an image an older version shows)
    before = shape

    result = Publishing::RestoreVersion.call(@page.reload, number: 2)

    assert_equal [ "Nothing to restore: the working version is already version 2." ], result.errors
    assert_equal before, shape
    assert_empty Audit::Event.where(action: "page.version_restored")
  end

  test "it records one event of its own with the number, and takes the settings row then the page's row first" do
    publish_two

    statements = capture_sql { restore(@page, 1) }

    event = Audit::Event.where(action: "page.version_restored", subject: @page).sole
    assert_equal({ "number" => 1 }, event.metadata)
    assert_nil event.snapshot
    settings = statements.index { |sql| sql.include?(%(FROM "site_settings")) && sql.include?("FOR SHARE") }
    lock = statements.index { |sql| sql.match?(/FROM "pages".*FOR UPDATE/m) }
    first_block_statement = statements.index { |sql| sql.include?(%("content_blocks")) }
    assert_operator settings, :<, lock
    assert_operator lock, :<, first_block_statement
  end

  test "a stale dialog is refused and writes nothing" do
    publish_two
    before = shape

    result = Publishing::RestoreVersion.call(@page.reload, number: 1, shown_updated_at: 1.minute.ago)

    assert_not result.ok?
    assert_not result.denied?
    assert_equal [ "This page changed since you opened this. Look at the differences again." ], result.errors
    assert_equal before, shape
    assert_empty Audit::Event.where(action: "page.version_restored")
  end

  test "the dialog's record, to the microsecond, is not stale" do
    publish_two

    restore(@page, 1, shown_updated_at: @page.reload.updated_at)

    assert_equal "Pricing", title(@page)
  end

  test "a post's stale dialog says post" do
    post = create_post(title: "Hello")

    result = Publishing::RestoreVersion.call(post, number: 1, shown_updated_at: 1.minute.ago)

    assert_equal [ "This post changed since you opened this. Look at the differences again." ], result.errors
  end

  test "a version that is no copy of the record, and one the rows already are, write nothing" do
    publish_two
    other = create_page(title: "Other")
    before = shape

    missing = Publishing::RestoreVersion.call(@page.reload, number: 3)
    elsewhere = Publishing::RestoreVersion.call(other, number: 2)
    same = Publishing::RestoreVersion.call(@page.reload, number: 2)

    assert_equal [ Publishing::RestoreVersion::NOT_FOUND ], missing.errors
    assert_equal [ Publishing::RestoreVersion::NOT_FOUND ], elsewhere.errors, "another record's number is not this one's"
    assert_equal [ "Nothing to restore: the working version is already version 2." ], same.errors
    assert_equal before, shape
    assert_empty Audit::Event.where(action: "page.version_restored")
  end

  test "someone with edit and not publish cannot restore a live page, and the refusal is audited" do
    publish_two
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "pages.edit", scope: {})
    before = shape

    result = as(users(:editor_branch)) { Publishing::RestoreVersion.call(@page.reload, number: 1) }

    assert result.denied?
    assert_equal before, shape
    denial = Audit::Event.where(action: "access.denied", subject: @page).sole
    assert_equal "pages.publish", denial.metadata["permission"]
    assert_empty Audit::Event.where(action: "page.version_restored")
  end

  # R7: a restore asks for an image as choosing one does (`Media::Choosing`),
  # and the refusal, which a step inside the transaction makes, is audited.
  test "someone without media.upload whose restore would bring back a changed image is refused, and the refusal is audited" do
    shown = create_media_asset
    later = create_media_asset
    image = add(nil, block_type: "image", media_asset_id: shown.id)
    publish_changes(@page)
    assert ContentBlocks::Save.call(image, attributes: { media_asset_id: later.id }).ok?
    assert Pages::Save.call(@page, translations: { "en" => { title: "Two" } }).ok?
    publish_changes(@page)
    %w[pages.edit pages.publish].each { |key| AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: key, scope: {}) }
    before = shape

    result = as(users(:editor_branch)) { Publishing::RestoreVersion.call(@page.reload, number: 2) }

    assert result.denied?
    assert_equal before, shape
    assert_equal later.id, image.reload.media_asset_id
    denial = Audit::Event.where(action: "access.denied").sole
    assert_equal "media.upload", denial.metadata["permission"]
    assert_equal @page, denial.subject
    assert_equal users(:editor_branch).id, denial.actor_id
    assert_empty Audit::Event.where(action: "page.version_restored")
  end

  test "a step that fails rolls everything back" do
    saved = BlockTypes.all.dup
    BlockTypes.register(:test_gone) { |t| TestTypes.declare(t); t.label "Test gone" }
    leaving = add(nil, block_type: "test_gone")
    publish_changes(@page)
    assert ContentBlocks::Destroy.call(leaving).ok?
    assert ContentBlocks::Destroy.call(@first).ok?
    publish_two
    BlockTypes.reset!
    saved.each { |definition| BlockTypes.registry_put(definition) }
    before = shape

    result = Publishing::RestoreVersion.call(@page.reload, number: 2)

    assert_not result.ok?
    assert_not result.denied?
    assert_includes result.errors, "Block type isn't a registered block type"
    assert_equal before, shape
    assert_equal "Two", title(@page)
    assert_empty Audit::Event.where(action: "page.version_restored")
  ensure
    BlockTypes.reset!
    saved&.each { |definition| BlockTypes.registry_put(definition) }
  end
end
