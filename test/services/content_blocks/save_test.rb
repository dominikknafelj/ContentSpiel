require "test_helper"

class ContentBlocks::SaveTest < ActiveSupport::TestCase
  test "appends to the end of the page's blocks when position is nil" do
    page = create_page(title: "Page")

    first = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" },
      translations: { "en" => { body: rich_doc("One") } })
    second = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" },
      translations: { "en" => { body: rich_doc("Two").to_json } })

    assert first.ok?
    assert second.ok?
    assert_equal 0, first.record.position
    assert_equal 1, second.record.position
    assert_equal rich_doc("One"), first.record.reload.body_document(locale: "en").to_h
    assert_equal rich_doc("Two"), second.record.reload.body_document(locale: "en").to_h
  end

  test "a position given on create is kept, not overridden" do
    page = create_page(title: "Page")
    page.content_blocks.create!(block_type: :rich_text, position: 0)

    result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text", position: 5 })

    assert result.ok?
    assert_equal 5, result.record.position
  end

  test "a post_list block with an unknown content type fails" do
    page = create_page(title: "Page")

    result = ContentBlocks::Save.call(ContentBlock.new(owner: page),
      attributes: { block_type: "post_list", settings: { "content_type" => "nope" } })

    assert_not result.ok?
    # The error is keyed "settings.content_type" (`ContentBlock
    # #settings_are_valid`), so its full message reads "Settings.content
    # type ..." -- humanized with a space, not the raw field name.
    assert result.errors.any? { |message| message.match?(/content.type/i) }
  end

  # --- An image block's library image (media library design spec §5.1) ---

  def image_block(page = create_page(title: "Page", published: false))
    as_owner { ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "image" }).record }
  end

  def block_usages(block) = Media::Usage.where(owner: block, role: "block_image").pluck(:media_asset_id)

  test "a media_asset_id sets the block's image and indexes its usage" do
    asset = create_media_asset
    block = image_block

    result = as_owner { ContentBlocks::Save.call(block, attributes: { media_asset_id: asset.id }) }

    assert result.ok?, result.errors.inspect
    assert_equal asset, block.reload.media_asset
    assert_equal [ asset.id ], block_usages(block)
    assert_equal asset.id, Audit::Event.where(action: "block.updated").last.snapshot["media_asset_id"]
  end

  test "an unknown media_asset_id fails validation" do
    block = image_block

    result = as_owner { ContentBlocks::Save.call(block, attributes: { media_asset_id: 0 }, translations: { "en" => { caption: "Changed" } }) }

    assert_not result.ok?
    assert_equal [ "Image doesn't exist" ], result.errors
    assert_nil block.reload.media_asset_id
    assert_nil block.caption
  end

  # Final fix wave (M1): the choose/delete race (see the same test in
  # `Pages::SaveTest`).
  test "an image deleted between the check and the save fails validation" do
    asset = create_media_asset
    block = image_block
    # The check is `Media::Asset.kept.exists?` (trashed images read as
    # missing), so the race is staged on what `.kept` returns.
    racing = Object.new
    racing.define_singleton_method(:exists?) { |*| Media::Asset.where(id: asset.id).delete_all.positive? }

    result = with_singleton_override(Media::Asset, :kept, ->(*) { racing }) do
      as_owner { ContentBlocks::Save.call(block, attributes: { media_asset_id: asset.id }, translations: { "en" => { caption: "Changed" } }) }
    end

    assert_not result.ok?
    assert_equal [ "Image doesn't exist" ], result.errors
    assert_nil block.reload.media_asset_id
    assert_nil block.caption
  end

  # Final fix wave (M1): the rich-text side of the race -- the body's image
  # passes validation and `UsageIndex`'s existence check, then goes before
  # the usage row is written (the FK on `media_usages`).
  test "a body image deleted before its usage row is written fails validation" do
    asset = create_media_asset
    block = as_owner { ContentBlocks::Save.call(ContentBlock.new(owner: create_page(title: "Page", published: false)), attributes: { block_type: "rich_text" }).record }
    insert_all = Media::Usage.method(:insert_all)
    racing = ->(rows, **options) { Media::Asset.where(id: asset.id).delete_all && insert_all.call(rows, **options) }

    result = with_singleton_override(Media::Usage, :insert_all, racing) do
      as_owner { ContentBlocks::Save.call(block, translations: { "en" => { body: rich_doc("::image{asset=\"#{asset.id}\"}") } }) }
    end

    assert_not result.ok?
    assert_equal [ "Body has an image that doesn't exist" ], result.errors
    assert block.reload.body_document(locale: "en").blank?
  end

  # Telling which FK refused the save is about row existence, not trash
  # state: a block still pointing at a *trashed* image (its row is there,
  # so its FK can't be what failed) must not be blamed for a body image
  # that vanished.
  test "a vanished body image isn't blamed on the block's own trashed image" do
    trashed = create_media_asset
    asset = create_media_asset
    block = as_owner { ContentBlocks::Save.call(ContentBlock.new(owner: create_page(title: "Page", published: false)), attributes: { block_type: "rich_text" }).record }
    block.update_columns(media_asset_id: trashed.id)
    trashed.update_columns(trashed_at: Time.current)
    insert_all = Media::Usage.method(:insert_all)
    racing = ->(rows, **options) { Media::Asset.where(id: asset.id).delete_all && insert_all.call(rows, **options) }

    result = with_singleton_override(Media::Usage, :insert_all, racing) do
      as_owner { ContentBlocks::Save.call(block.reload, translations: { "en" => { body: rich_doc("::image{asset=\"#{asset.id}\"}") } }) }
    end

    assert_not result.ok?
    assert_equal [ "Body has an image that doesn't exist" ], result.errors
  end

  test "an actor without media.upload can't set the image, but can clear it" do
    asset = create_media_asset
    block = image_block
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "pages.edit", scope: {})

    refused = as(users(:editor_branch)) { ContentBlocks::Save.call(block, attributes: { media_asset_id: asset.id }) }
    assert refused.denied?
    assert_equal [ "You don't have permission to upload media" ], refused.errors
    assert_nil block.reload.media_asset_id

    as_owner { ContentBlocks::Save.call(block, attributes: { media_asset_id: asset.id }) }
    cleared = as(users(:editor_branch)) { ContentBlocks::Save.call(block, attributes: { media_asset_id: "" }) }
    assert cleared.ok?, cleared.errors.inspect
    assert_nil block.reload.media_asset_id
    assert_empty block_usages(block)
  end

  test "a rich-text block's body images are indexed per locale, and deleting the block removes them" do
    asset = create_media_asset
    page = create_page(title: "Page")

    block = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" },
      translations: { "de" => { body: rich_doc("::image{asset=\"#{asset.id}\"}") } }).record
    assert_equal [ [ asset.id, "de" ] ], Media::Usage.where(owner: block, role: "rich_text").pluck(:media_asset_id, :locale)

    assert ContentBlocks::Destroy.call(block).ok?
    assert_empty Media::Usage.where(owner_type: "ContentBlock", owner_id: block.id)
  end

  def section_on(page, layout: "three")
    ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "section", settings: { "layout" => layout } }, actor: nil).record
  end

  def add_to(section, column, type: "rich_text")
    ContentBlocks::Save.call(ContentBlock.new(owner: section.owner), attributes: { block_type: type, section_id: section.id, section_column: column }, actor: nil)
  end

  test "a new block goes to the end of the column it names" do
    page = create_page(title: "Columns")
    section = section_on(page)
    first = add_to(section, 2).record
    second = add_to(section, 2).record
    other = add_to(section, 1).record

    assert_equal [ [ section.id, 2, 0 ], [ section.id, 2, 1 ], [ section.id, 1, 0 ] ],
      [ first, second, other ].map { |block| [ block.section_id, block.section_column, block.position ] }
    assert_equal page, first.owner
  end

  test "a new top-level block is appended among the top-level blocks" do
    page = create_page(title: "Top")
    section = section_on(page)
    3.times { add_to(section, 1) }
    text = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }, actor: nil).record

    assert_equal [ section, text ], page.content_blocks.top_level.reorder(:position).to_a
    assert_equal 1, text.position
  end

  test "a column the section no longer has is refused and nothing is written" do
    page = create_page(title: "Gone column")
    section = section_on(page, layout: "two")

    assert_no_difference -> { ContentBlock.count } do
      result = add_to(section, 3)
      assert_not result.ok?
      assert_not result.denied?
      assert_includes result.errors.to_sentence, "isn't a column of this section"
    end
  end

  test "a section can't be created inside a section, and an existing block's section can't be changed through a save" do
    page = create_page(title: "Rules")
    section = section_on(page)
    assert_not add_to(section, 1, type: "section").ok?

    text = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }, actor: nil).record
    assert ContentBlocks::Save.call(text, attributes: { section_id: section.id, section_column: 1 }, actor: nil).ok?
    assert_nil text.reload.section_id
  end

  test "a layout with fewer columns moves the removed columns' blocks to the end of the last one, in column order" do
    page = create_page(title: "Fold")
    section = section_on(page, layout: "four")
    keep = add_to(section, 2).record
    third_a = add_to(section, 3).record
    third_b = add_to(section, 3).record
    fourth = add_to(section, 4).record

    result = nil
    assert_difference -> { Audit::Event.where(action: "block.updated").count }, 1 do
      result = ContentBlocks::Save.call(section, attributes: { settings: { "layout" => "two" } }, actor: nil)
    end

    assert result.ok?
    assert_equal [ keep, third_a, third_b, fourth ], page.content_blocks.in_column(section, 2).reorder(:position).to_a
    assert_equal [ 0, 1, 2, 3 ], page.content_blocks.in_column(section, 2).reorder(:position).pluck(:position)
    assert_equal [ third_a.id, third_b.id, fourth.id ], Audit::Event.where(action: "block.updated").last.metadata["folded_block_ids"]
    assert_equal 4, ContentBlock.where(section_id: section.id).count
  end

  test "a layout with as many or more columns moves nothing" do
    page = create_page(title: "Widen")
    section = section_on(page, layout: "two")
    block = add_to(section, 2).record

    assert ContentBlocks::Save.call(section, attributes: { settings: { "layout" => "one_two" } }, actor: nil).ok?
    assert ContentBlocks::Save.call(section, attributes: { settings: { "layout" => "four" } }, actor: nil).ok?
    assert_equal [ 2, 0 ], block.reload.then { |b| [ b.section_column, b.position ] }
  end

  test "a save into a column needs the page's edit right like any block" do
    page = create_page(title: "Rights", published: false)
    section = section_on(page)
    nobody = User.create!(email_address: "nobody-columns@example.com", password: "a long enough password")

    result = as(nobody) { ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text", section_id: section.id, section_column: 1 }) }

    assert_predicate result, :denied?
    assert_empty ContentBlock.where(section_id: section.id)
  end

  # The plan's review focus (decision D14): one tab folds a section to fewer
  # columns while another adds into the last one. Both take the page's row
  # lock first, so the add runs after the fold has committed and is judged
  # against the layout as it then stands: refused with a message, and no
  # block is left in a column the section does not have.
  test "an add into a column that a fold has just removed is refused, and no block is left beyond the layout" do
    page = create_page(title: "Two tabs")
    section = section_on(page, layout: "three")
    there = add_to(section, 3).record

    assert ContentBlocks::Save.call(section, attributes: { settings: { "layout" => "two" } }, actor: nil).ok?
    result = add_to(section, 3)

    assert_not result.ok?
    assert_equal [ "Section column isn't a column of this section" ], result.errors
    assert_equal [ [ there.id, 2 ] ], ContentBlock.where(section_id: section.id).pluck(:id, :section_column)
  end

  # The other half of the same race: the second tab still holds the section
  # as it was loaded before the first tab widened it and a block arrived in
  # the new column. Its save writes the old, narrower layout; the fold is
  # decided from the rows under the lock, not from what that stale object
  # remembers, so the block comes along.
  test "a section saved from a copy loaded before it was widened still folds what arrived since" do
    page = create_page(title: "Stale tab")
    section = section_on(page, layout: "two")
    stale = ContentBlock.find(section.id)
    assert ContentBlocks::Save.call(section, attributes: { settings: { "layout" => "four" } }, actor: nil).ok?
    arrived = add_to(section, 4).record

    assert ContentBlocks::Save.call(stale, attributes: { settings: { "layout" => "two", "background" => "tinted" } }, actor: nil).ok?

    assert_equal [ 2, 0 ], arrived.reload.then { |b| [ b.section_column, b.position ] }
    assert_equal %w[two tinted], section.reload.settings.values_at("layout", "background")
  end

  # The same stale copy, sending nothing but the layout it already believes
  # in. Judged against that copy the settings are unchanged, no UPDATE would
  # be issued and the row would keep "four" while its blocks were folded to
  # two columns. The section is re-read under the lock, so the save is the
  # narrowing it looks like: the row says "two", the event says so too.
  test "a stale copy that sends only the layout it already holds narrows the stored section and folds, as one event" do
    page = create_page(title: "Stale layout")
    section = section_on(page, layout: "two")
    stale = ContentBlock.find(section.id)
    assert ContentBlocks::Save.call(section, attributes: { settings: { "layout" => "four" } }, actor: nil).ok?
    third = add_to(section, 3).record
    fourth = add_to(section, 4).record

    assert_difference -> { Audit::Event.where(action: "block.updated").count }, 1 do
      assert ContentBlocks::Save.call(stale, attributes: { settings: { "layout" => "two" } }, actor: nil).ok?
    end

    assert_equal "two", section.reload.settings["layout"]
    assert_equal [ [ third.id, 2, 0 ], [ fourth.id, 2, 1 ] ], ContentBlock.where(section_id: section.id).reorder(:position).pluck(:id, :section_column, :position)
    event = Audit::Event.where(action: "block.updated").last
    assert_equal [ third.id, fourth.id ], event.metadata["folded_block_ids"]
    assert_equal %w[four two], event.field_changes["settings"].map { |settings| settings["layout"] }
  end

  # `block.updated` coalesces: a burst of saves of one section is one row,
  # and a row's `metadata` is written once, when the row is (the log is
  # append-only outside the coalescing columns). A fold folded into an
  # earlier row would lose the ids of the blocks it moved, in the commonest
  # order of all -- a section's look is adjusted, then its layout. So a save
  # that folded is always a row of its own.
  test "a fold just after another save of the section is its own event, naming the blocks it moved" do
    page = create_page(title: "Look, then layout")
    section = section_on(page, layout: "three")
    third = add_to(section, 3).record
    assert ContentBlocks::Save.call(section, attributes: { settings: { "background" => "tinted" } }, actor: nil).ok?

    assert_difference -> { Audit::Event.where(action: "block.updated", subject: section).count }, 1 do
      assert ContentBlocks::Save.call(section, attributes: { settings: { "layout" => "two" } }, actor: nil).ok?
    end

    look, fold = Audit::Event.where(action: "block.updated", subject: section).order(:id).to_a
    assert_equal({}, look.metadata)
    assert_equal %w[none tinted], look.field_changes["settings"].map { |settings| settings["background"] }
    assert_equal [ third.id ], fold.metadata["folded_block_ids"]
    assert_equal %w[three two], fold.field_changes["settings"].map { |settings| settings["layout"] }
  end

  # The other order. A later ordinary save does coalesce into the fold's
  # row, as into any open `block.updated` of the section: that extends its
  # field changes, snapshot and count and leaves `metadata` as written.
  test "a save of the section just after a fold extends the fold's event and leaves its folded ids alone" do
    page = create_page(title: "Layout, then look")
    section = section_on(page, layout: "three")
    third = add_to(section, 3).record
    assert ContentBlocks::Save.call(section, attributes: { settings: { "layout" => "two" } }, actor: nil).ok?

    assert_no_difference -> { Audit::Event.where(action: "block.updated", subject: section).count } do
      assert ContentBlocks::Save.call(section, attributes: { settings: { "background" => "tinted" } }, actor: nil).ok?
    end

    event = Audit::Event.where(action: "block.updated", subject: section).sole
    assert_equal [ third.id ], event.metadata["folded_block_ids"]
    assert_equal 2, event.occurrences
    assert_equal [ %w[three none], %w[two tinted] ], event.field_changes["settings"].map { |settings| settings.values_at("layout", "background") }
  end

  test "two folds in a row are two events, each naming its own blocks" do
    page = create_page(title: "Narrow twice")
    section = section_on(page, layout: "three")
    second = add_to(section, 2).record
    third = add_to(section, 3).record

    assert ContentBlocks::Save.call(section, attributes: { settings: { "layout" => "two" } }, actor: nil).ok?
    assert ContentBlocks::Save.call(section, attributes: { settings: { "layout" => "one" } }, actor: nil).ok?

    assert_equal [ [ third.id ], [ second.id, third.id ] ],
      Audit::Event.where(action: "block.updated", subject: section).order(:id).map { |event| event.metadata["folded_block_ids"] }
  end

  # And a save that does not name the layout at all moves nothing, whatever
  # the copy it was made from believes the layout to be.
  test "a stale copy's save that leaves the layout alone folds nothing and keeps the stored layout" do
    page = create_page(title: "Stale background")
    section = section_on(page, layout: "two")
    stale = ContentBlock.find(section.id)
    idle = ContentBlock.find(section.id)
    assert ContentBlocks::Save.call(section, attributes: { settings: { "layout" => "four" } }, actor: nil).ok?
    fourth = add_to(section, 4).record

    assert ContentBlocks::Save.call(stale, attributes: { settings: { "background" => "strong" } }, actor: nil).ok?
    assert_no_difference -> { Audit::Event.count } do
      assert ContentBlocks::Save.call(idle, actor: nil).ok?
    end

    assert_equal %w[four strong], section.reload.settings.values_at("layout", "background")
    assert_equal [ 4, 0 ], fourth.reload.then { |b| [ b.section_column, b.position ] }
  end

  test "a section deleted by another tab is a failure for the save that still holds it, not an exception" do
    page = create_page(title: "Gone section")
    section = section_on(page)
    stale = ContentBlock.find(section.id)
    assert ContentBlocks::Destroy.call(section, actor: nil).ok?

    result = ContentBlocks::Save.call(stale, attributes: { settings: { "layout" => "two" } }, actor: nil)

    assert_not result.ok?
    assert_equal [ "This block no longer exists" ], result.errors
  end

  test "a save that creates a block locks the page's row before it writes, in a section or at the top level" do
    page = create_page(title: "Lock")
    section = section_on(page)
    locks = ->(statements) { statements.index { |sql| sql.match?(/FROM "pages".*FOR UPDATE/m) } }
    first_write = ->(statements) { statements.index { |sql| sql.match?(/\A(INSERT INTO|UPDATE) "content_blocks"/) } }

    into_column = capture_sql { assert add_to(section, 1).ok? }
    layout = capture_sql { assert ContentBlocks::Save.call(section, attributes: { settings: { "layout" => "two" } }, actor: nil).ok? }
    new_section = capture_sql { section_on(page) }
    outside = capture_sql { assert ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }, actor: nil).ok? }

    [ into_column, layout, new_section, outside ].each do |statements|
      assert_operator locks.call(statements), :<, first_write.call(statements)
      assert_equal 0, statements.index { |sql| !sql.match?(/SAVEPOINT|BEGIN/) }.then { |first| locks.call(statements) - first }, "the lock is the transaction's first statement"
    end
  end

  # The lock order. A fold, a lift and a section's
  # delete take the page's row and then write block rows -- the blocks in
  # the section, and (a lift, the renumbering after a delete) the top-level
  # blocks around it. An ordinary save used to write its own row and then
  # take the page's (the owner's touch). Two tabs doing one each could wait
  # on each other until Postgres aborted one. So the page's row comes first
  # for every block's save, wherever the block is.
  test "an ordinary save of a block locks the page's row before its own, in a section and at the top level" do
    page = create_page(title: "Lock order")
    section = section_on(page)
    inside = add_to(section, 3).record
    outside = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }, actor: nil).record
    typing = { "en" => { body: rich_doc("Typed") } }

    in_section = capture_sql { assert ContentBlocks::Save.call(inside, translations: typing, actor: nil).ok? }
    top_level = capture_sql { assert ContentBlocks::Save.call(outside, translations: typing, actor: nil).ok? }

    [ in_section, top_level ].each do |statements|
      lock = statements.index { |sql| sql.match?(/FROM "pages".*FOR UPDATE/m) }
      write = statements.index { |sql| sql.start_with?('UPDATE "content_blocks"') }
      assert_operator lock, :<, write
      assert_equal 1, statements.count { |sql| sql.match?(/FROM "pages".*FOR UPDATE/m) }
      assert_equal 1, statements.count { |sql| sql.start_with?('UPDATE "content_blocks"') }
    end
  end

  # A block handed over with a page that isn't saved yet has no row to lock:
  # the save goes on as it always did (the page is saved with its block).
  test "a block of a page that is not saved yet is saved without a lock query, as before" do
    page = Page.new(parent: root_page, title: "Unsaved owner")
    statements = nil

    result = nil
    assert_difference -> { Page.count } => 1, -> { ContentBlock.count } => 1 do
      statements = capture_sql { result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }, actor: nil) }
    end

    assert result.ok?, result.errors.inspect
    assert_empty statements.grep(/FROM "pages".*FOR UPDATE/m)
  end
end
