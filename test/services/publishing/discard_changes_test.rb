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
      [ block["block_type"], sections.index(block["section_id"]), block["section_column"], block["settings"], block["translated_settings"],
        with_text(block["body"]), block["caption"], block["alt"], block["media_asset_id"], block["listed_tag_id"] ]
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

  # -- tags are references, followed by id; none is ever made (fix round 1, C1 and I2) --

  def live_post(tags)
    Posts::Save.call(attributes: { content_type: "blog", published: true, tag_names: tags },
      translations: { "en" => { title: "Hello", excerpt: "Short", body: rich_doc("Body") } }).record
  end

  test "a post gets its text and its fields back, and its tags by id: a renamed tag under its present name, and the mark stays for the name the copy still shows" do
    post = live_post(%w[ruby rails])
    assert Posts::Save.call(post, attributes: { tag_names: %w[other] }, translations: { "en" => { title: "Typed", body: rich_doc("Typed") }, "de" => { title: "Getippt" } }).ok?
    ruby = Tag.find_by!(name: "ruby")
    assert Tags::Rename.call(ruby, name: "rubies").ok?
    tags = Tag.count

    result = Publishing::DiscardChanges.call(post.reload)

    assert result.ok?, result.errors.to_sentence
    post.reload
    assert_equal({ "en" => "Hello" }, post.read_attribute(:title).compact_blank)
    assert_equal "Body", post.body_document(locale: "en").to_markdown.strip
    assert_equal %w[rails rubies], post.tags.pluck(:name).sort
    assert_equal Publishing.current(post).tag_ids, post.tags.pluck(:id).sort, "the same tags, by id"
    assert_equal tags, Tag.count, "no tag was made"
    # What is left is the rename itself: the copy says "ruby" until the post is published again.
    assert_equal %w[tags], Publishing::Changes.of(post).fields
    assert post.unpublished_changes?, "so the mark stays"
    assert_equal Publishing::DiscardChanges::REMAINS, result.notice
  end

  test "with nothing renamed, merged or deleted the tags go back, the mark is gone and the result says nothing more" do
    post = live_post(%w[ruby rails])
    assert Posts::Save.call(post, attributes: { tag_names: %w[other] }).ok?

    result = Publishing::DiscardChanges.call(post.reload)

    assert result.ok?
    assert_nil result.notice
    assert_equal %w[rails ruby], post.reload.tags.pluck(:name).sort
    assert_not post.unpublished_changes?
    assert Publishing::Changes.of(post).none?
  end

  # The review's sequence: published with alpha and gamma, alpha merged into
  # beta, any edit, discard.
  test "after a merge a discard leaves the post on the KEPT tag: the merged tag is not made again, and publishing afterwards changes no list and no address" do
    Tag.create!(name: "beta")
    listing = create_page(title: "Topic", published: false)
    assert ContentBlocks::Save.call(ContentBlock.new(owner: listing), attributes: { block_type: "post_list", settings: { "content_type" => "blog", "tag" => "beta" } }).ok?
    assert Pages::Save.call(listing, attributes: { published: true }).ok?
    post = live_post(%w[alpha gamma])
    assert Tags::Merge.call(Tag.find_by!(name: "alpha"), into: Tag.find_by!(name: "beta")).ok?
    beta = Tag.find_by!(name: "beta")
    assert_equal "/topic/hello", post.reload.full_path("en")
    assert Posts::Save.call(post, translations: { "en" => { title: "Typed" } }).ok?
    tags = Tag.count

    result = Publishing::DiscardChanges.call(post.reload)

    assert result.ok?, result.errors.to_sentence
    post.reload
    assert_equal %w[beta gamma], post.tags.pluck(:name).sort
    assert_includes post.tags.pluck(:id), beta.id
    assert_equal Publishing.current(post).tag_ids, post.tags.pluck(:id).sort
    assert_nil Tag.find_by(name: "alpha"), "the merged tag did not come back"
    assert_equal tags, Tag.count
    assert_equal "Hello", Mobility.with_locale(:en) { post.title }
    assert_equal %w[beta gamma], Publishing.current(post).snapshot["tags"].map { |tag| tag["name"] }.sort, "the merge rewrote the copy's names too"
    assert_not post.unpublished_changes?, "so the rows are the copy again and nothing is left to publish"
    assert_nil result.notice

    paths = PublicPath.current.order(:id).pluck(:record_type, :record_id, :locale, :path)
    listed = Publishing::Listing.blocks.flat_map { |block| Publishing::Listing.posts(block).map(&:id) }.sort
    publish_changes(post)
    assert_equal paths, PublicPath.current.order(:id).pluck(:record_type, :record_id, :locale, :path), "publishing afterwards moves no address"
    assert_equal listed, Publishing::Listing.blocks.flat_map { |block| Publishing::Listing.posts(block).map(&:id) }.sort, "and changes no list"
    assert_not post.reload.unpublished_changes?
    assert Publishing::Changes.of(post).none?
  end

  test "after a merge a discard leaves a list block filtering by the KEPT tag, under its present name, and publishing afterwards keeps the list and the addresses" do
    Tag.create!(name: "beta")
    list = add(nil, block_type: "post_list", settings: { "content_type" => "blog", "tag" => "alpha" })
    post = live_post(%w[alpha])
    publish_changes(@page)
    assert_equal "/pricing/hello", post.reload.full_path("en")
    assert Tags::Merge.call(Tag.find_by!(name: "alpha"), into: Tag.find_by!(name: "beta")).ok?
    beta = Tag.find_by!(name: "beta")
    assert Pages::Save.call(@page, translations: { "en" => { title: "Typed" } }).ok?
    tags = Tag.count

    result = Publishing::DiscardChanges.call(@page.reload)

    assert result.ok?, result.errors.to_sentence
    assert_equal "beta", list.reload.settings["tag"]
    assert_equal beta.id, list.listed_tag_id
    assert_equal beta.id, Publishing.current(@page).blocks.find { |block| block["id"] == list.id }["listed_tag_id"], "the id the copy recorded, repointed by the merge"
    assert_equal tags, Tag.count
    assert_nil Tag.find_by(name: "alpha")
    assert_equal "Pricing", Mobility.with_locale(:en) { @page.reload.title }
    assert @page.unpublished_changes?, "the copy's block still says alpha by name"
    assert_equal Publishing::DiscardChanges::REMAINS, result.notice

    publish_changes(@page)
    assert_equal "/pricing/hello", post.reload.full_path("en"), "the list still lists the post"
    assert Publishing::Changes.of(@page.reload).none?
  end

  test "after a rename a list block whose filter was corrected to the new name keeps filtering by that tag" do
    list = add(nil, block_type: "post_list", settings: { "content_type" => "blog", "tag" => "alpha" })
    post = live_post(%w[alpha])
    publish_changes(@page)
    alpha = Tag.find_by!(name: "alpha")
    assert Tags::Rename.call(alpha, name: "omega").ok?
    assert ContentBlocks::Save.call(list.reload, attributes: { settings: { "content_type" => "blog", "tag" => "omega" } }).ok?
    assert Pages::Save.call(@page, translations: { "en" => { title: "Typed" } }).ok?

    result = Publishing::DiscardChanges.call(@page.reload)

    assert result.ok?, result.errors.to_sentence
    assert_equal "omega", list.reload.settings["tag"]
    assert_equal alpha.id, list.listed_tag_id
    assert_equal 1, Tag.where(name: %w[alpha omega]).count
    assert @page.reload.unpublished_changes?

    publish_changes(@page)
    assert_equal "/pricing/hello", post.reload.full_path("en")
  end

  test "a tag deleted since stays deleted: the post goes back without it, the list block's filter names no tag, the mark stays and the result says why" do
    list = add(nil, block_type: "post_list", settings: { "content_type" => "blog", "tag" => "alpha" })
    post = live_post(%w[alpha gamma])
    publish_changes(@page)
    assert Tags::Destroy.call(Tag.find_by!(name: "alpha")).ok?
    assert Posts::Save.call(post, translations: { "en" => { title: "Typed" } }).ok?
    assert Pages::Save.call(@page, translations: { "en" => { title: "Typed" } }).ok?
    tags = Tag.count

    of_post = Publishing::DiscardChanges.call(post.reload)
    of_page = Publishing::DiscardChanges.call(@page.reload)

    assert of_post.ok? && of_page.ok?
    assert_equal tags, Tag.count
    assert_nil Tag.find_by(name: "alpha"), "a deleted tag never comes back"
    assert_equal %w[gamma], post.reload.tags.pluck(:name)
    assert_equal "Hello", Mobility.with_locale(:en) { post.title }
    assert_equal %w[tags], Publishing::Changes.of(post).fields
    assert post.unpublished_changes?
    assert_equal Publishing::DiscardChanges::REMAINS, of_post.notice
    assert_equal "alpha", list.reload.settings["tag"], "written as the copy has it: a name no tag has"
    assert_nil list.listed_tag_id
    assert_equal "Pricing", Mobility.with_locale(:en) { @page.reload.title }
    assert @page.unpublished_changes?
    assert_equal Publishing::DiscardChanges::REMAINS, of_page.notice
  end

  test "when all that differs is what cannot be put back, a discard writes nothing, records nothing, keeps the mark and says why" do
    post = live_post(%w[ruby])
    assert Tags::Rename.call(Tag.find_by!(name: "ruby"), name: "rubies").ok?
    assert post.reload.unpublished_changes?
    events = Audit::Event.count
    updated_at = post.updated_at

    result = Publishing::DiscardChanges.call(post)

    assert_not result.ok?
    assert_equal [ Publishing::DiscardChanges::REMAINS ], result.errors
    assert_equal events, Audit::Event.count
    assert_equal updated_at, post.reload.updated_at
    assert post.unpublished_changes?
  end

  # -- what the dialog showed (fix round 1, I1) ----------------------------------

  test "a discard that was shown no scheduled change is refused when one was scheduled since, and writes nothing" do
    assert Pages::Save.call(@page, translations: { "en" => { title: "Typed" } }).ok?
    publish_changes(@page, at: 2.days.from_now)
    events = Audit::Event.count

    result = Publishing::DiscardChanges.call(@page.reload, shown_pending: nil)

    assert_not result.ok?
    assert_not result.denied?
    assert_equal [ Publishing::ShownSchedule::MOVED ], result.errors
    assert Publishing.pending(@page), "the colleague's scheduled change is still there"
    assert_equal "Typed", Mobility.with_locale(:en) { @page.reload.title }
    assert_equal events, Audit::Event.count

    assert Publishing::DiscardChanges.call(@page.reload, shown_pending: Publishing.pending(@page).id).ok?, "shown the change, it goes with the rest"
    assert_nil Publishing.pending(@page)
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
