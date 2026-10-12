require "test_helper"

# Who may discard is the service contract's business; the refusal under
# someone else's hold is the controller's (`test/integration/admin/publishing_test.rb`).
class Publishing::DiscardChangesTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing", published: false)
    @first = add("First")
    @section = add(nil, block_type: "section", settings: { "layout" => "three" })
    @left = add("Left", section_id: @section.id, section_column: 1)
    @middle = add("Middle", section_id: @section.id, section_column: 2)
    @right = add("Right", section_id: @section.id, section_column: 3)
    @last = add("Last")
    assert Pages::Save.call(@page, attributes: { published: true }, translations: { "en" => { subtitle: "Plans" }, "de" => { title: "Preise" } }).ok?
    @published = shape
  end

  def add(text, **attributes)
    result = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" }.merge(attributes),
      translations: (text ? { "en" => { body: rich_doc(text) } } : {}))
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  # The page as a visitor would be shown it, without ids: every block's type,
  # place and text in reading order, and the page's own fields. Without the
  # translation bookkeeping, which a discard does not copy back (it is what
  # the save services leave), and with a language that holds an empty
  # document read as a language with none: a body is emptied by writing an
  # empty document, and a visitor is shown the same nothing.
  def shape
    data = Publishing::Snapshot.of(@page.reload)
    sections = data["blocks"].select { |block| block["block_type"] == "section" }.map { |block| block["id"] }
    [ data["fields"].except(*Publishable::BOOKKEEPING), data["blocks"].map do |block|
      [ block["block_type"], sections.index(block["section_id"]), block["section_column"], block["settings"], with_text(block["body"]), block["caption"] ]
    end ]
  end

  def with_text(body) = body.to_h.reject { |_locale, document| document["content"].blank? }

  def discard
    result = Publishing::DiscardChanges.call(@page.reload)
    assert result.ok?, result.errors.to_sentence
    changes = Publishing::Changes.of(@page.reload)
    assert changes.none?, "after a discard nothing differs from what is published: #{changes.fields.inspect} #{changes.blocks.map(&:kind).inspect}"
    assert_not @page.unpublished_changes?
  end

  test "changed fields and changed text go back, in every language, and the mark is gone" do
    assert Pages::Save.call(@page, attributes: { page_type: "landing" }, translations: { "en" => { title: "Typed", subtitle: "" }, "de" => { title: "Getippt" }, "es" => { title: "Nuevo" } }).ok?
    assert ContentBlocks::Save.call(@first, translations: { "en" => { body: rich_doc("Typed") }, "de" => { body: rich_doc("Getippt") } }).ok?

    discard

    assert_equal @published, shape
    assert_equal({ "en" => "Pricing", "de" => "Preise" }, @page.reload.read_attribute(:title).compact_blank)
    assert_not @page.unpublished_changes?
    assert Publishing::Changes.of(@page).none?
    assert_equal @first.id, @page.content_blocks.reorder(:position, :id).first.id, "a block that stayed keeps its id"
  end

  test "a block added since is deleted, and a block deleted since comes back as a new block in its place" do
    add("Added")
    assert ContentBlocks::Destroy.call(@first).ok?

    discard

    assert_equal @published, shape
    assert_not ContentBlock.exists?(@first.id)
  end

  test "a block that came back under a new id is the block it was: a second discard keeps it and its notes" do
    assert ContentBlocks::Destroy.call(@first).ok?
    discard
    back = @page.content_blocks.top_level.reorder(:position, :id).first
    assert_not_equal @first.id, back.id
    as(users(:two)) { assert Notes::Start.call(back, body: "A note").ok? }
    add("Added")

    discard

    assert ContentBlock.exists?(back.id)
    assert_equal [ back ], Notes::Thread.all.map(&:subject)
    assert_equal @published, shape
  end

  test "a block deleted from a section comes back in its column and place" do
    assert ContentBlocks::Destroy.call(@middle).ok?
    extra = add("Second in the right column", section_id: @section.id, section_column: 3)
    assert ContentBlocks::Reorder.call(@page, [ extra.id, @right.id ], section: @section.id, column: 3).ok?

    discard

    assert_equal @published, shape
  end

  test "a section removed with its blocks kept comes back with them inside" do
    assert ContentBlocks::Destroy.call(@section, keep_blocks: true).ok?

    discard

    assert_equal @published, shape
    assert_equal [ @left.id, @middle.id, @right.id ].sort, ContentBlock.where(owner: @page).where.not(section_id: nil).ids.sort, "the blocks that were kept are the ones put back"
  end

  test "a section deleted with its blocks comes back with new blocks inside" do
    assert ContentBlocks::Destroy.call(@section).ok?

    discard

    assert_equal @published, shape
  end

  test "a narrowed section is wide again with its blocks in their columns, and a new section goes while a block put into it stays" do
    assert ContentBlocks::Save.call(@section, attributes: { settings: { "layout" => "one" } }).ok?
    other = add(nil, block_type: "section", settings: { "layout" => "two" })
    assert ContentBlocks::Reorder.call(@page, [ @last.id ], section: other.id, column: 1, moved_from: { @last.id => { section_id: nil, column: nil } }).ok?

    discard

    assert_equal @published, shape
    assert ContentBlock.exists?(@last.id)
    assert_not ContentBlock.exists?(other.id)
  end

  test "blocks moved about, between containers and within them, are where they were" do
    assert ContentBlocks::Reorder.call(@page, [ @last.id, @section.id, @first.id ]).ok?
    assert ContentBlocks::Reorder.call(@page, [ @right.id, @left.id ], section: @section.id, column: 1, moved_from: { @right.id => { section_id: @section.id, column: 3 } }).ok?
    assert ContentBlocks::Reorder.call(@page, [ @first.id, @middle.id ], section: @section.id, column: 2, moved_from: { @first.id => { section_id: nil, column: nil } }).ok?

    discard

    assert_equal @published, shape
  end

  test "a post gets its text, its fields and its tags back, a renamed tag under its present name" do
    post = Posts::Save.call(attributes: { content_type: "blog", published: true, tag_names: %w[ruby rails] },
      translations: { "en" => { title: "Hello", excerpt: "Short", body: rich_doc("Body") } }).record
    assert Posts::Save.call(post, attributes: { tag_names: %w[other] }, translations: { "en" => { title: "Typed", body: rich_doc("Typed") }, "de" => { title: "Getippt" } }).ok?
    Tag.find_by!(name: "ruby").update!(name: "rubies")

    assert Publishing::DiscardChanges.call(post.reload).ok?

    post.reload
    assert_equal({ "en" => "Hello" }, post.read_attribute(:title).compact_blank)
    assert_equal "Body", post.body_document(locale: "en").to_markdown.strip
    assert_equal %w[rails rubies], post.tags.pluck(:name).sort
    assert_not post.unpublished_changes?
    # What is left is the rename itself: the copy says "ruby" until the post is published again.
    assert_equal %w[tags], Publishing::Changes.of(post).fields
  end

  # The dispatch of Task 7 reverses the brief here ("it returns to changes
  # that are scheduled, not to what is on the site now"): a discard goes back
  # to the copy IN FORCE and withdraws a change that is scheduled.
  test "it returns to what is on the site now, and a change that was scheduled is withdrawn with it" do
    assert Pages::Save.call(@page, translations: { "en" => { title: "Scheduled title" } }).ok?
    publish_changes(@page, at: 2.days.from_now)
    assert Pages::Save.call(@page, translations: { "en" => { title: "Typed after" } }).ok?

    discard

    assert_equal "Pricing", Mobility.with_locale(:en) { @page.reload.title }
    assert_nil Publishing.pending(@page)
    assert_equal 1, Publishing.baseline(@page).number
    assert_equal :live, Publishing::State.of(@page).state
    event = Audit::Event.where(action: "page.changes_discarded", subject: @page).last
    assert_equal({ "number" => 1, "withdrawn_number" => 2 }, event.metadata)
  end

  test "a change that is scheduled is discarded although nothing was typed since" do
    assert Pages::Save.call(@page, translations: { "en" => { title: "Scheduled title" } }).ok?
    publish_changes(@page, at: 2.days.from_now)
    assert_not @page.reload.unpublished_changes?

    discard

    assert_equal @published, shape
    assert_nil Publishing.pending(@page)
  end

  test "an image only the withdrawn change showed is no longer in use" do
    asset = create_media_asset
    image = add(nil, block_type: "image", media_asset_id: asset.id)
    publish_changes(@page, at: 2.days.from_now)
    assert Media::Usage.exists?(media_asset_id: asset.id, owner: @page, role: "published")

    discard

    assert_not ContentBlock.exists?(image.id)
    assert_empty Media::Usage.where(media_asset_id: asset.id)
    assert_equal @published, shape
  end

  test "a discard that fails half way leaves the rows as they were" do
    add("Added")
    assert ContentBlocks::Destroy.call(@first).ok?
    before = shape
    failing = ->(*, **) { ApplicationService::Result.failure(@page, [ "No" ]) }

    result = with_singleton_override(ContentBlocks::Reorder, :call, failing) { Publishing::DiscardChanges.call(@page.reload) }

    assert_not result.ok?
    assert_equal [ "No" ], result.errors
    assert_equal before, shape
    assert @page.reload.unpublished_changes?
    assert_empty Audit::Event.where(action: "page.changes_discarded")
  end

  test "a draft and a record with no copy have nothing to discard" do
    draft = create_page(title: "Draft", published: false)

    result = Publishing::DiscardChanges.call(draft)

    assert_not result.ok?
    assert_not result.denied?
  end

  test "it records one event of its own, with the number it returned to, and takes the page's row lock first" do
    assert ContentBlocks::Save.call(@first, translations: { "en" => { body: rich_doc("Typed") } }).ok?

    statements = capture_sql { discard }

    assert_equal 1, Audit::Event.where(action: "page.changes_discarded", subject: @page).last.metadata["number"]
    lock = statements.index { |sql| sql.match?(/FROM "pages".*FOR UPDATE/m) }
    first_block_statement = statements.index { |sql| sql.include?(%("content_blocks")) }
    assert_operator lock, :<, first_block_statement
  end

  test "a mark left by typing and typing back is cleared, nothing is written and no event says a discard happened" do
    assert Pages::Save.call(@page, translations: { "en" => { title: "Typed" } }).ok?
    assert Pages::Save.call(@page, translations: { "en" => { title: "Pricing" } }).ok?
    assert @page.reload.unpublished_changes?

    result = Publishing::DiscardChanges.call(@page)

    assert_not result.ok?
    assert_equal [ "There is nothing to discard" ], result.errors
    assert_not @page.reload.unpublished_changes?
    assert_empty Audit::Event.where(action: "page.changes_discarded")
  end

  test "a language typed since is emptied again, and an emptied body is no change" do
    assert ContentBlocks::Save.call(@first, translations: { "es" => { body: rich_doc("Nuevo"), caption: "Pie" } }).ok?
    assert Publishing::Changes.of(@page.reload).locales.include?("es")

    discard

    assert @first.reload.body_document(locale: "es").blank?
    assert_nil @first.read_attribute(:caption).to_h["es"].presence
    assert Publishing::Changes.of(@page.reload).none?
  end

  test "nothing public moves: the content version, the addresses and what a visitor is shown are as before" do
    assert Pages::Save.call(@page, translations: { "en" => { title: "Typed" } }).ok?
    add("Added")
    version = PublicSite.content_version
    paths = PublicPath.order(:id).pluck(:id, :locale, :path, :record_type, :record_id)
    copies = Publishing::Version.count

    discard

    assert_equal version, PublicSite.content_version
    assert_equal paths, PublicPath.order(:id).pluck(:id, :locale, :path, :record_type, :record_id)
    assert_equal copies, Publishing::Version.count
  end

  test "the slug, the place in the tree and the publish state are immediate and are not discarded" do
    other = create_page(title: "Other")
    assert Pages::Save.call(@page, translations: { "en" => { slug: "prices", title: "Typed" } }).ok?
    assert Pages::Move.call(@page, parent: other, position: 0).ok?
    at = @page.reload.published_at

    discard

    @page.reload
    assert_equal "prices", Mobility.with_locale(:en) { @page.slug }
    assert_equal other.id, @page.parent_id
    assert_equal at, @page.published_at
    assert_equal "Pricing", Mobility.with_locale(:en) { @page.title }
  end

  test "a block added since is deleted with its notes, and the notes of a block that stayed are kept" do
    added = add("Added")
    as(users(:two)) { [ added, @first ].each { |block| assert Notes::Start.call(block, body: "A note").ok? } }

    discard

    assert_equal [ @first ], Notes::Thread.all.map(&:subject)
  end

  # Translation bookkeeping is not copied back from the copy: it is what the
  # save services leave when the text is written back.
  test "a translation confirmed since the last publish stays confirmed by a discard that does not touch its text" do
    assert Pages::Save.call(@page, translations: { "en" => { title: "Pricing plans" } }).ok?
    publish_changes(@page)
    assert Translations::Confirm.call(@page.reload, field: "title", locale: "de").ok?
    confirmed = @page.reload.translation_sources
    assert_not_equal Publishing.current(@page).snapshot.dig("fields", "translation_sources"), confirmed, "the confirmation is newer than the copy"
    assert Pages::Save.call(@page, attributes: { page_type: "landing" }).ok?

    discard

    assert_equal confirmed, @page.reload.translation_sources
    assert_equal "standard", @page.page_type
  end

  test "where the original's text goes back, the services mark it as for any edit: the time is theirs, not the copy's" do
    copied = Publishing.current(@page).snapshot.dig("fields", "translation_original_changed_at")
    assert Pages::Save.call(@page, translations: { "en" => { title: "Typed" } }).ok?

    discard

    assert_equal "Pricing", Mobility.with_locale(:en) { @page.reload.title }
    assert_not_equal copied, @page.translation_original_changed_at
    assert @page.translation_original_changed_at.key?("title")
  end

  test "a scheduled page goes back to what was scheduled" do
    scheduled = create_page(title: "Later", published: false)
    assert Pages::Save.call(scheduled, attributes: { published_at: 3.days.from_now }).ok?
    assert Pages::Save.call(scheduled, translations: { "en" => { title: "Typed" } }).ok?

    assert Publishing::DiscardChanges.call(scheduled.reload).ok?

    assert_equal "Later", Mobility.with_locale(:en) { scheduled.reload.title }
    assert_not scheduled.unpublished_changes?
  end
end
