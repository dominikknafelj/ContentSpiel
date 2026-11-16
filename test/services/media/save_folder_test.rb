require "test_helper"

# `Media::SaveFolder`: creating, renaming and moving a library folder, under
# the tree's lock, with the depth, count and name rules judged from one read of
# the whole tree.
class Media::SaveFolderTest < ActiveSupport::TestCase
  def save(folder = nil, **attributes) = as_owner { Media::SaveFolder.call(folder, attributes: attributes) }

  def folder!(name, parent: nil) = Media::Folder.create!(name: name, parent_id: parent&.id)

  # A chain of folders, each inside the one before, `names` long.
  def chain(*names)
    names.each_with_object([]) { |name, folders| folders << folder!(name, parent: folders.last) }
  end

  test "a holder of media.manage creates a folder at the top and inside another, each audited once" do
    top = save(name: "Trips")
    assert top.ok?, top.errors.inspect
    inner = save(name: "Italy", parent_id: top.record.id)
    assert inner.ok?, inner.errors.inspect

    assert_nil top.record.parent_id
    assert_equal top.record.id, inner.record.parent_id
    events = Audit::Event.where(action: "media_folder.created").order(:id)
    assert_equal 2, events.size
    assert_equal %w[Trips Italy], events.map { |event| event.snapshot["name"] }
    assert_equal [ nil, top.record.id ], events.map { |event| event.snapshot["parent_id"] }
    assert_equal "Media::Folder", events.first.subject_type
  end

  test "media.upload alone may not create, rename or move a folder" do
    folder = folder!("Trips")
    target = folder!("Target")
    uploader = users(:author)
    assert AccessControl.allowed?(uploader, "media.upload", nil)
    assert_not AccessControl.allowed?(uploader, "media.manage", nil)

    attempts = [
      -> { Media::SaveFolder.call(attributes: { name: "New" }) },
      -> { Media::SaveFolder.call(folder, attributes: { name: "Renamed" }) },
      -> { Media::SaveFolder.call(folder, attributes: { parent_id: target.id }) }
    ]
    attempts.each do |attempt|
      before = Media::Folder.order(:id).pluck(:id, :name, :parent_id)
      # A refusal coalesces into the one before it, so occurrences are counted.
      denied = -> { Audit::Event.where(action: "access.denied").sum(:occurrences) }
      denials = denied.call
      others = Audit::Event.where.not(action: "access.denied").count
      result = as(uploader) { attempt.call }

      assert result.denied?
      assert_equal before, Media::Folder.order(:id).pluck(:id, :name, :parent_id)
      assert_equal denials + 1, denied.call
      assert_equal others, Audit::Event.where.not(action: "access.denied").count
    end
  end

  test "a sibling's name in another case is refused on the name, and the index's race is the same failure" do
    folder!("Trips")
    result = save(name: "trips")

    assert_not result.ok?
    assert_equal [ "A folder named “trips” is already here." ], result.record.errors[:name]
    assert_equal [ "A folder named “trips” is already here." ], result.errors
    assert_equal 1, Media::Folder.count

    # The same name under another parent is another name.
    assert save(name: "Trips", parent_id: Media::Folder.first.id).ok?

    # The pre-check is what the lock makes certain; with it stubbed away the
    # unique index is the one that refuses, and the answer is the same.
    raced = as_owner do
      service = Media::SaveFolder.new(attributes: { name: "TRIPS" })
      service.define_singleton_method(:name_taken?) { false }
      service.call
    end

    assert_not raced.ok?
    assert_equal [ "A folder named “TRIPS” is already here." ], raced.record.errors[:name]
    assert_equal 2, Media::Folder.count
  end

  test "renaming records the old and the new name and is never coalesced" do
    folder = folder!("Trips")
    assert save(folder, name: "Journeys").ok?
    assert save(folder, name: "Voyages").ok?

    events = Audit::Event.where(action: "media_folder.renamed").order(:id)
    assert_equal 2, events.size
    assert_equal [ { "name" => [ "Trips", "Journeys" ] }, { "name" => [ "Journeys", "Voyages" ] } ], events.map(&:field_changes)
    assert_equal "Voyages", folder.reload.name
  end

  test "a move records the new parent and a move to the top says so" do
    into = folder!("2026")
    folder = folder!("Trips")
    assert save(folder, parent_id: into.id).ok?
    assert save(folder, parent_id: nil).ok?

    moved, to_top = Audit::Event.where(action: "media_folder.moved").order(:id).to_a
    assert_equal({ "parent_id" => [ nil, into.id ] }, moved.field_changes)
    assert_equal "2026", moved.metadata["parent"]
    assert_equal({ "parent_id" => [ into.id, nil ] }, to_top.field_changes)
    assert_nil to_top.metadata["parent"]
  end

  test "a folder moved inside itself or below its own subfolder is refused" do
    top, below = chain("Top", "Below")

    inside_itself = save(top, parent_id: top.id)
    assert_not inside_itself.ok?
    assert_equal [ "A folder can't go inside itself." ], inside_itself.record.errors[:parent_id]

    inside_its_own = save(top, parent_id: below.id)
    assert_not inside_its_own.ok?
    assert_equal [ "A folder can't go inside itself." ], inside_its_own.errors
    assert_nil top.reload.parent_id
  end

  test "a move whose deepest folder would sit at level 5 is refused" do
    *, level3 = chain("One", "Two", "Three")
    subtree = chain("Fresh", "Fresher")

    result = save(subtree.first, parent_id: level3.id)

    assert_not result.ok?
    assert_equal [ "That would nest folders more than 4 levels deep." ], result.record.errors[:parent_id]
    assert_nil subtree.first.reload.parent_id

    # One level shallower fits: a single folder under level 3 sits at level 4.
    assert save(subtree.last, parent_id: level3.id).ok?
    # And a new folder under that level 4 would be the fifth.
    too_deep = save(name: "Fifth", parent_id: subtree.last.id)
    assert_not too_deep.ok?
    assert_equal [ "That would nest folders more than 4 levels deep." ], too_deep.errors
  end

  test "a parent that names no folder is refused on parent_id" do
    result = save(name: "Orphan", parent_id: 999_999)

    assert_not result.ok?
    assert_equal [ "That folder is gone." ], result.record.errors[:parent_id]
    assert_equal 0, Media::Folder.count
  end

  test "a folder deleted before the save is gone, not an error page" do
    folder = folder!("Trips")
    Media::Folder.where(id: folder.id).delete_all

    result = save(folder, name: "Journeys")

    assert_not result.ok?
    assert_equal [ "That folder is gone." ], result.errors
  end

  test "the name is judged as the model judges it" do
    assert_equal [ "Give the folder a name." ], save(name: "  ").errors
    assert_equal [ "Use at most 80 characters." ], save(name: "x" * 81).errors
    assert_equal 0, Media::Folder.count
    assert_equal "Trips", save(name: "  Trips ").record.name
  end

  test "the 1,001st folder is refused" do
    stub_const(Media::Folder, :MAX_FOLDERS, 2) do
      folder!("One")
      folder!("Two")

      result = save(name: "Three")

      assert_not result.ok?
      assert_equal [ "A site holds at most 1,000 folders." ], result.errors
      assert_equal 2, Media::Folder.count
      # A rename of an existing folder is no new one.
      assert save(Media::Folder.first, name: "Uno").ok?
    end
  end

  test "every tree write takes the tree's lock first" do
    folder = folder!("Trips")

    statements = capture_sql { assert save(folder, name: "Journeys").ok? }
    lock = statements.index { |sql| sql.include?("LOCK TABLE media_folders IN SHARE ROW EXCLUSIVE MODE") }
    write = statements.index { |sql| sql.match?(/\A\s*(INSERT INTO|UPDATE) "media_folders"/) }

    assert lock, "the tree was never locked"
    assert write
    assert_operator lock, :<, write

    statements = capture_sql { assert save(name: "Fresh").ok? }
    assert_operator statements.index { |sql| sql.include?("LOCK TABLE media_folders") }, :<, statements.index { |sql| sql.start_with?('INSERT INTO "media_folders"') }
  end
end
