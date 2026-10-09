require "test_helper"

# `Trash::Purge` (trash spec §4.3): the permanent delete, reachable only
# from the trash. Absorbs what `Pages::Destroy`'s and `Media::Destroy`'s own
# tests covered -- usages cleaned up with their owners, an image refused
# while anything (a trashed owner included) still uses it, the foreign key
# backing that up when the usage index is behind.
class Trash::PurgeTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup { Current.actor = users(:one) }

  def upload_by(user)
    file = Rack::Test::UploadedFile.new(file_fixture("tiny.png"), "image/png")
    result = Media::Upload.call(file: file, actor: user)
    assert result.ok?, result.errors.inspect
    result.record
  end

  test "a page branch goes for good, deepest first, with blocks and usages" do
    asset = create_media_asset
    parent = create_page(title: "Section")
    child = create_page(title: "Child", parent: parent)
    block = ContentBlock.create!(owner: child, block_type: "image", position: 1, media_asset: asset)
    Media::UsageIndex.refresh(block)
    assert asset.used?
    assert Trash::Move.call(parent).ok?

    result = Trash::Purge.call(parent.reload)

    assert result.ok?, result.errors.to_sentence
    assert_not Page.exists?(parent.id)
    assert_not Page.exists?(child.id)
    assert_not ContentBlock.exists?(block.id)
    assert_not Media::Usage.exists?(media_asset_id: asset.id)
    assert Audit::Event.where(action: "page.purged", subject_id: parent.id).exists?
  end

  # The order of locks for a page's blocks is the page's row, then block
  # rows (`ContentBlocks::Save#call`). A page's destroy deletes its blocks
  # and then its own row, so without a lock taken first it would hold a
  # block and wait for the page while a block save holds the page and waits
  # for the block. Every page of the branch is locked in one statement, in
  # id order, before anything of it is deleted.
  test "the branch's pages are locked, in id order, before the first block is deleted" do
    parent = create_page(title: "Section")
    child = create_page(title: "Child", parent: parent)
    [ parent, child ].each { |page| ContentBlock.create!(owner: page, block_type: "rich_text", position: 0) }
    assert Trash::Move.call(parent).ok?

    statements = capture_sql { assert Trash::Purge.call(parent.reload).ok? }

    locks = statements.each_index.select { |index| statements[index].match?(/FROM "pages".*FOR UPDATE/m) }
    assert_equal 1, locks.size
    assert_match(/ORDER BY "pages"."id" ASC/, statements[locks.first])
    assert_operator locks.first, :<, statements.index { |sql| sql.start_with?('DELETE FROM "content_blocks"') }
    assert_operator locks.first, :<, statements.index { |sql| sql.start_with?('DELETE FROM "pages"') }
  end

  # Carried over from `Pages::Destroy`: the page's own hero row goes too,
  # not only its blocks'.
  test "a page's own hero usage goes with it" do
    asset = create_media_asset
    page = create_page(title: "Leaf")
    assert Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id }).ok?
    assert ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "image", media_asset_id: asset.id }).ok?
    assert_equal 2, asset.usages.count
    assert Trash::Move.call(page).ok?

    assert Trash::Purge.call(page.reload).ok?
    assert_equal 0, asset.usages.count
  end

  # Every page a branch purge destroys leaves its own trace in the audit
  # log -- members and separately trashed descendants alike -- pointing
  # back at the page the editor actually purged; the root's event lists
  # them all.
  test "a branch purge records one page.purged per page" do
    parent = create_page(title: "Section")
    child = create_page(title: "Child", parent: parent)
    grandchild = create_page(title: "Grandchild", parent: child)
    loner = create_page(title: "Loner", parent: parent)
    assert Trash::Move.call(loner).ok?
    assert Trash::Move.call(parent.reload).ok?

    assert Trash::Purge.call(parent.reload).ok?

    root_event = Audit::Event.find_by!(action: "page.purged", subject_id: parent.id)
    assert_equal [ child.id, grandchild.id, loner.id ].sort, root_event.metadata["descendant_ids"].sort
    [ child, grandchild, loner ].each do |page|
      events = Audit::Event.where(action: "page.purged", subject_type: "Page", subject_id: page.id)
      assert_equal 1, events.count, page.title
      assert_equal "Page##{parent.id}", events.first.metadata["purged_with"]
    end
  end

  test "a separately trashed descendant goes with the branch" do
    parent = create_page(title: "Section")
    child = create_page(title: "Child", parent: parent)
    assert Trash::Move.call(child).ok?
    assert Trash::Move.call(parent.reload).ok?

    assert Trash::Purge.call(parent.reload).ok?
    assert_not Page.exists?(child.id)
  end

  test "a branch with a kept page under it is refused, and nothing goes" do
    parent = create_page(title: "Section")
    child = create_page(title: "Child", parent: parent)
    assert Trash::Move.call(parent).ok?
    child.update_columns(trashed_at: nil, trash_root_id: nil)

    result = Trash::Purge.call(parent.reload)

    assert_not result.ok?
    assert_equal [ "A page under it isn't in the trash" ], result.errors
    assert Page.exists?(parent.id)
    assert Page.exists?(child.id)
    assert_not Audit::Event.exists?(action: "page.purged")
  end

  # Purging a subpage out of a branch still in the trash would leave that
  # branch's later restore incomplete: it's the branch root that goes.
  test "a page trashed as part of another page's branch is refused, naming the root" do
    parent = create_page(title: "Section")
    child = create_page(title: "Child", parent: parent)
    assert Trash::Move.call(parent).ok?

    result = Trash::Purge.call(child.reload)

    assert_not result.ok?
    assert_not result.denied?
    assert_equal [ "Delete “Section” permanently to remove this page" ], result.errors
    assert Page.exists?(child.id)
    assert_not Audit::Event.exists?(action: "page.purged")
  end

  # Not found, not forbidden: an actor who may delete the subpage but
  # can't read the branch root isn't told the root's title.
  test "the refusal doesn't name a root the actor can't read" do
    parent = create_page(title: "Secret section")
    child = create_page(title: "Child", parent: parent)
    %w[pages.read pages.delete].each do |key|
      AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: key, scope: { "page_ids" => [ child.id ] })
    end
    assert Trash::Move.call(parent).ok?

    result = Trash::Purge.call(child.reload, actor: users(:editor_branch))

    assert_not result.ok?
    assert_not result.denied?
    assert_equal [ "Delete the page it was moved to the trash with permanently to remove this page" ], result.errors
    assert Page.exists?(child.id)
  end

  # Once the root is gone (or back out of the trash), a leftover member is
  # no longer part of anyone's pending restore.
  test "a branch member whose root isn't in the trash any more can go" do
    parent = create_page(title: "Section")
    child = create_page(title: "Child", parent: parent)
    assert Trash::Move.call(parent).ok?
    parent.update_columns(trashed_at: nil, trash_root_id: nil)

    assert Trash::Purge.call(child.reload).ok?
    assert_not Page.exists?(child.id)
  end

  test "a kept record can't be purged" do
    post = create_post(title: "Here")

    result = Trash::Purge.call(post)

    assert_not result.ok?
    assert_not result.denied?
    assert_equal [ "Only items in the trash can be deleted permanently" ], result.errors
    assert Post.exists?(post.id)
  end

  test "a post goes with its tags' join rows and records post.purged" do
    post = create_post(title: "Bye", tags: [ "ruby" ])
    assert Trash::Move.call(post).ok?

    assert Trash::Purge.call(post.reload).ok?
    assert_not Post.exists?(post.id)
    assert_not PostTag.exists?(post_id: post.id)
    assert_equal "Bye", Audit::Event.find_by!(action: "post.purged").snapshot.dig("title", "en")
  end

  test "posts.delete is needed for a post" do
    post = create_post(title: "Guarded")
    assert Trash::Move.call(post).ok?

    result = as(users(:reader)) { Trash::Purge.call(post.reload) }

    assert result.denied?
    assert Post.exists?(post.id)
    assert Audit::Event.exists?(action: "access.denied")
  end

  test "an image used by a trashed page can't be purged until that page is" do
    asset = create_media_asset
    page = create_page(title: "Hero page")
    assert Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id }).ok?
    assert Trash::Move.call(page).ok?
    assert Trash::Move.call(asset.reload).ok?

    refused = Trash::Purge.call(asset.reload)
    assert_not refused.ok?
    assert_match(/\AThis image is used on /, refused.errors.first)
    assert Trash::Purge.call(page.reload).ok?
    assert Trash::Purge.call(asset.reload).ok?
    assert_not Media::Asset.exists?(asset.id)
  end

  # Carried over from `Media::DestroyTest`: `Media::Asset#in_use_message`
  # names three places, counts the rest, and names a block's usage by the
  # page or post it sits on -- here every owner is itself in the trash.
  test "the refusal lists three usages and counts the rest, blocks named by their page or post" do
    asset = upload_by(users(:author))
    owners = %w[One Two Three].map do |title|
      page = create_page(title: title)
      assert Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id }).ok?
      page
    end
    four = create_page(title: "Four")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: four), attributes: { block_type: "image", media_asset_id: asset.id }).ok?
    five = create_post(title: "Five")
    assert Posts::Save.call(five, translations: { "en" => { body: rich_doc("::image{asset=\"#{asset.id}\"}") } }).ok?
    [ *owners, four, five ].each { |owner| assert Trash::Move.call(owner).ok? }
    assert Trash::Move.call(asset.reload).ok?

    result = as(users(:two)) { Trash::Purge.call(asset.reload) }

    assert_not result.ok?
    assert_equal [ "This image is used on the page “One”, the page “Two”, the page “Three” and 2 more" ], result.errors
  end

  # "Not found, not forbidden": a place the acting user can't read is named
  # neutrally, never by its title.
  test "a place the actor can't read is named neutrally" do
    asset = upload_by(users(:author))
    page = create_page(title: "Secret")
    assert Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id }).ok?
    assert Trash::Move.call(page).ok?
    assert Trash::Move.call(asset.reload).ok?
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "media.manage", scope: {})

    result = as(users(:editor_branch)) { Trash::Purge.call(asset.reload) }

    assert_not result.ok?
    assert_not result.denied?
    assert_equal [ "This image is used on a page you can't open" ], result.errors
  end

  test "an unused image goes, records media.purged and purges the file after commit" do
    asset = upload_by(users(:author))
    blob = asset.file.blob
    assert as(users(:two)) { Trash::Move.call(asset) }.ok?

    result = nil
    assert_difference "Media::Asset.count", -1 do
      result = as(users(:two)) { Trash::Purge.call(asset.reload) }
    end

    assert result.ok?, result.errors.inspect
    event = Audit::Event.find_by!(action: "media.purged")
    assert_equal "tiny", event.subject_label
    assert_equal "tiny.png", event.snapshot["filename"]
    assert_enqueued_with(job: ActiveStorage::PurgeJob, args: [ blob ])
  end

  test "the uploader purges their own upload without media.manage" do
    asset = upload_by(users(:author))
    assert as(users(:author)) { Trash::Move.call(asset) }.ok?

    assert as(users(:author)) { Trash::Purge.call(asset.reload) }.ok?
    assert_not Media::Asset.exists?(asset.id)
  end

  test "someone else without media.manage is denied" do
    asset = upload_by(users(:one))
    assert Trash::Move.call(asset).ok?

    result = as(users(:author)) { Trash::Purge.call(asset.reload) }

    assert result.denied?
    assert_equal [ "You don't have permission to manage media" ], result.errors
    assert Media::Asset.exists?(asset.id)
    assert_not Audit::Event.exists?(action: "media.purged")
  end

  # Review Focus 4 of the media library: the usage index is behind (a race,
  # a raw write) -- the service's own check passes, the FK still restricts,
  # and the database error becomes a failure rather than a 500.
  test "an unindexed reference is caught by the foreign key and fails cleanly" do
    asset = upload_by(users(:author))
    assert Trash::Move.call(asset).ok?
    page = create_page(title: "Raced")
    page.update_column(:hero_media_asset_id, asset.id)
    assert_not asset.used?

    result = Trash::Purge.call(asset.reload)

    assert_not result.ok?
    assert_equal [ "This image is still in use" ], result.errors
    assert Media::Asset.exists?(asset.id)
    assert asset.reload.file.attached?
    assert_not Audit::Event.exists?(action: "media.purged")
    assert_no_enqueued_jobs(only: ActiveStorage::PurgeJob)
  end

  # A destroy halted by a callback without adding an error (`throw :abort`)
  # still answers with a message about deleting -- not the generic "could
  # not be saved".
  test "a destroy halted without errors fails with a deletion message" do
    asset = upload_by(users(:author))
    assert Trash::Move.call(asset).ok?
    asset.reload

    result = with_singleton_override(asset, :destroy, -> { false }) { Trash::Purge.call(asset) }

    assert_not result.ok?
    assert_equal [ "This image couldn't be deleted" ], result.errors
    assert Media::Asset.exists?(asset.id)
    assert_not Audit::Event.exists?(action: "media.purged")
  end

  test "trash.empty allows purging any single item without the item's own delete right" do
    emptier = User.create!(email_address: "emptier@example.com", password: "a-long-enough-password")
    group = AccessControl::Group.create!(name: "Trash emptiers")
    AccessControl::Grant.create!(group: group, permission: "trash.empty", scope: {})
    AccessControl::Membership.create!(user: emptier, group: group)
    trashed = create_post(title: "Gone")
    assert Trash::Move.call(trashed).ok?
    kept = create_post(title: "Staying")

    purged = as(emptier) { Trash::Purge.call(trashed.reload) }
    assert purged.ok?, purged.errors.to_sentence
    assert_not Post.exists?(trashed.id)

    moved = as(emptier) { Trash::Move.call(kept) }
    assert moved.denied?
    assert_not kept.reload.trashed?
  end

  test "a purged page takes its notes and its blocks' notes; a child's go with the branch" do
    page = create_page(title: "Noted", published: false)
    child = create_page(title: "Child", parent: page, published: false)
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)
    keep = create_page(title: "Keep")
    as(users(:two)) do
      [ page, child, block, keep ].each { |subject| Notes::Start.call(subject, body: "A note, @[#{users(:reader).id}]") }
    end
    assert Trash::Move.call(page).ok?

    assert Trash::Purge.call(page.reload).ok?

    assert_equal [ keep ], Notes::Thread.all.map(&:subject)
    assert_equal [ 1, 1, 2 ], [ Notes::Message.count, Notes::Delivery.count, Notes::Follow.count ]
    assert_equal 1, Audit::Event.where(action: "notes.removed").count
  end

  test "a purged post and a purged image take their notes" do
    post = create_post(title: "Noted", published: false)
    asset = create_media_asset
    as(users(:two)) { [ post, asset ].each { |subject| Notes::Start.call(subject, body: "A note") } }

    [ post, asset ].each do |record|
      assert Trash::Move.call(record).ok?
      assert Trash::Purge.call(record.reload).ok?
    end

    assert_equal 0, Notes::Thread.count
  end

  # `Notes::Remove` checks the purge's own right again. A `pages.delete`
  # scoped to a branch is matched against the page's closure rows, which the
  # page's destroy deletes: checked after the destroy it would refuse the
  # very person the purge had just allowed, and roll the purge back.
  test "someone whose delete right reaches one branch only purges a page of it, notes and all" do
    page = create_page(title: "Branch", published: false)
    as(users(:two)) { Notes::Start.call(page, body: "A note") }
    assert Trash::Move.call(page).ok?
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "pages.delete", scope: { "page_ids" => [ page.id ] })

    result = as(users(:editor_branch)) { Trash::Purge.call(page.reload) }

    assert result.ok?, result.errors.to_sentence
    assert_equal [ 0, 0 ], [ Notes::Thread.count, Page.where(id: page.id).count ]
  end

  # The test above passes wherever the call stands: `Trash::Purge` asks the
  # right of the object it was handed, and Rails keeps that object's
  # `self_and_ancestor_ids` from the first time it is read (the purge's own
  # check), so the second answer does not come from the closure rows. That
  # is a detail of Active Record, not a rule of this app, and anything that
  # hands `Notes::Remove` a fresh copy of the page would lose it. So the
  # order itself is pinned here, and what a fresh read answers is shown.
  test "the notes are removed before the first page of the branch is deleted" do
    page = create_page(title: "Branch", published: false)
    child = create_page(title: "Leaf", parent: page, published: false)
    as(users(:two)) { [ page, child ].each { |subject| Notes::Start.call(subject, body: "A note") } }
    assert Trash::Move.call(page).ok?
    page.reload

    statements = capture_sql { assert Trash::Purge.call(page).ok? }

    locked = statements.index { |sql| sql.include?('FROM "pages"') && sql.include?("FOR UPDATE") }
    notes = statements.index { |sql| sql.start_with?('DELETE FROM "note_threads"') }
    first_page = statements.index { |sql| sql.start_with?('DELETE FROM "pages"') }
    assert_operator locked, :<, notes
    assert_operator notes, :<, first_page
    assert_equal 1, statements.count { |sql| sql.start_with?('DELETE FROM "note_threads"') }
  end

  # A post and an image go the other way round from a page: destroyed first,
  # then their notes removed. The destroy's own lock on the row is what a
  # note being started waits on, and the purge takes no row lock of its own
  # -- one taken before the destroy would meet `Posts::Save`, which writes a
  # post's join rows before the post, the wrong way round.
  test "a post and an image are deleted before their notes are touched, and the purge locks neither row itself" do
    { create_post(title: "Noted", published: false, tags: %w[one]) => "posts", create_media_asset => "media_assets" }.each do |record, table|
      as(users(:two)) { Notes::Start.call(record, body: "A note") }
      assert Trash::Move.call(record).ok?
      record.reload

      statements = capture_sql { assert Trash::Purge.call(record).ok? }

      deleted = statements.index { |sql| sql.start_with?(%(DELETE FROM "#{table}")) }
      first_note = statements.index { |sql| sql.include?('"note_threads"') }
      assert_operator deleted, :<, first_note, table
      assert_equal 1, statements.count { |sql| sql.start_with?('DELETE FROM "note_threads"') }
      assert_empty statements.select { |sql| sql.include?(%(FROM "#{table}")) && sql.include?("FOR UPDATE") }, table
    end
  end

  def notes_left = [ Notes::Thread.count, Notes::Message.count, Notes::Follow.count, Notes::Delivery.count ]

  def member_with(email, grants)
    user = User.create!(email_address: email, password: "a-long-enough-password")
    group = AccessControl::Group.create!(name: "Group of #{email}")
    grants.each { |permission, scope| AccessControl::Grant.create!(group: group, permission: permission, scope: scope) }
    AccessControl::Membership.create!(user: user, group: group)
    user
  end

  # `Notes::Remove` asks the purge's right again of the post or image the
  # purge has just destroyed. Every way of holding that right is read from
  # the object in memory (the content type, the author, the uploader) or
  # from no record at all, so each of these still answers as it did before.
  test "a purged post takes its notes for the owner, an Admin, a holder scoped to its type and their own, and a trash.empty holder" do
    scoped = member_with("scoped@example.com", "posts.read" => {}, "posts.create" => {},
      "posts.delete" => { "content_types" => [ "blog" ], "own" => true })
    emptier = member_with("emptier@example.com", "trash.empty" => {})

    [ users(:one), users(:two), scoped, emptier ].each do |actor|
      post = as(actor == scoped ? scoped : users(:one)) { create_post(title: "Noted #{actor.id}", published: false) }
      as(users(:two)) { Notes::Start.call(post, body: "A note, @[#{users(:reader).id}]") }
      assert Trash::Move.call(post).ok?

      result = as(actor) { Trash::Purge.call(post.reload) }

      assert result.ok?, "#{actor.email_address}: #{result.errors.to_sentence}"
      assert_equal [ 0, 0, 0, 0, 0 ], [ *notes_left, Post.where(id: post.id).count ], actor.email_address
    end
    assert_equal 0, Audit::Event.where(action: "access.denied", user: [ users(:one), users(:two), scoped ]).count
  end

  test "a purged image takes its notes for the owner, an Admin, its uploader, and a trash.empty holder" do
    emptier = member_with("emptier@example.com", "trash.empty" => {})

    [ users(:one), users(:two), users(:author), emptier ].each do |actor|
      asset = actor == users(:author) ? upload_by(actor) : create_media_asset
      as(users(:two)) { Notes::Start.call(asset, body: "A note, @[#{users(:author).id}]") }
      assert Trash::Move.call(asset).ok?

      result = as(actor) { Trash::Purge.call(asset.reload) }

      assert result.ok?, "#{actor.email_address}: #{result.errors.to_sentence}"
      assert_equal [ 0, 0, 0, 0, 0 ], [ *notes_left, Media::Asset.where(id: asset.id).count ], actor.email_address
    end
  end

  test "asked once the page is deleted, a right that reaches one branch only is not found" do
    page = create_page(title: "Branch", published: false)
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "pages.delete", scope: { "page_ids" => [ page.id ] })
    assert Trash::Move.call(page).ok?
    before = Page.find(page.id)
    assert Trash::Purge.call(page.reload).ok?

    assert_predicate as(users(:editor_branch)) { Notes::Remove.call(before) }, :denied?
  end

  test "a purge that is refused keeps the notes" do
    page = create_page(title: "Noted", published: false)
    as(users(:two)) { Notes::Start.call(page, body: "A note") }

    assert_not Trash::Purge.call(page).ok? # not in the trash
    assert_equal 1, Notes::Thread.count
  end

  test "moving to the trash and restoring keep the notes" do
    page = create_page(title: "Noted", published: false)
    as(users(:two)) { Notes::Start.call(page, body: "A note") }

    assert Trash::Move.call(page).ok?
    assert_equal 1, Notes::Thread.count
    assert Trash::Restore.call(page.reload).ok?
    assert_equal 1, Notes::Thread.count
  end

  test "a purge costs the same statements with one note as with many" do
    counts = [ 1, 6 ].map do |notes|
      page = create_page(title: "Noted #{notes}", published: false)
      as(users(:two)) { notes.times { Notes::Start.call(page, body: "A note") } }
      assert Trash::Move.call(page).ok?
      page.reload
      capture_sql { assert Trash::Purge.call(page).ok? }.size
    end

    assert_equal counts.first, counts.last
  end
end
