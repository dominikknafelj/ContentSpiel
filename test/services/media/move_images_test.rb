require "test_helper"

# `Media::MoveImages` (docs/reference/media.md): the one writer of an image's
# folder after an upload. All or nothing, at most 200 images, kept images
# only, and no touch of `updated_at` or the content version.
class Media::MoveImagesTest < ActiveSupport::TestCase
  def move(ids, folder, actor: users(:one)) = as(actor) { Media::MoveImages.call(asset_ids: Array(ids), folder: folder) }

  def uploaded_by(user)
    file = Rack::Test::UploadedFile.new(file_fixture("tiny.png"), "image/png")
    result = Media::Upload.call(file: file, actor: user)
    assert result.ok?, result.errors.inspect
    result.record
  end

  def events = Audit::Event.where(action: "media.moved").order(:id)

  test "an editor moves images into a folder and each gets one media.moved with the folder change" do
    folder = Media::Folder.create!(name: "Client A")
    first, second = create_media_asset, create_media_asset

    result = move([ first.id, second.id ], folder)

    assert result.ok?, result.errors.inspect
    assert_nil result.record
    assert_equal [ first.id, second.id ], result.moved.map(&:id)
    assert_equal [ folder.id, folder.id ], [ first, second ].map { |asset| asset.reload.folder_id }
    assert_equal [ [ first.id, second.id ], [ [ nil, folder.id ] ] * 2, [ "Client A" ] * 2 ],
      [ events.map(&:subject_id), events.map { |event| event.field_changes["folder_id"] }, events.map { |event| event.metadata["folder_name"] } ]

    out = move([ first.id ], nil)

    assert out.ok?
    assert_nil first.reload.folder_id
    assert_equal [ folder.id, nil ], events.last.field_changes["folder_id"]
    assert_nil events.last.metadata["folder_name"]
  end

  test "an image already in the target is left alone and records nothing" do
    folder = Media::Folder.create!(name: "Client A")
    asset = create_media_asset
    assert move([ asset.id ], folder).ok?

    assert_no_difference -> { events.count } do
      result = move([ asset.id ], folder)

      assert result.ok?
      assert_empty result.moved
    end
  end

  test "an uploader moves their own images, and one image not theirs refuses the whole move" do
    folder = Media::Folder.create!(name: "Client A")
    mine, other_mine = uploaded_by(users(:author)), uploaded_by(users(:author))
    theirs = uploaded_by(users(:one))

    assert move([ mine.id, other_mine.id ], folder, actor: users(:author)).ok?
    assert_equal [ folder.id ] * 2, [ mine, other_mine ].map { |asset| asset.reload.folder_id }

    assert_no_difference -> { events.count } do
      assert_difference -> { Audit::Event.where(action: "access.denied").count }, 1 do
        result = move([ mine.id, theirs.id ], nil, actor: users(:author))

        assert_predicate result, :denied?
        assert_equal [ "1 of these images is not yours to move. Nothing was moved." ], result.errors
      end
    end
    assert_equal folder.id, mine.reload.folder_id

    other_theirs = uploaded_by(users(:one))
    result = move([ theirs.id, other_theirs.id ], nil, actor: users(:author))
    assert_equal [ "2 of these images are not yours to move. Nothing was moved." ], result.errors
    assert_nil theirs.reload.folder_id
  end

  test "more than 200 ids are refused before anything is read" do
    result = nil
    statements = capture_sql { result = move((1..201).to_a, nil) }

    assert_not result.ok?
    assert_equal [ "Move at most 200 images at once." ], result.errors
    assert_empty statements.grep(/media_assets/)
  end

  test "a trashed or missing id is refused as missing and nothing moves" do
    folder = Media::Folder.create!(name: "Client A")
    kept, trashed = create_media_asset, create_media_asset
    assert as_owner { Trash::Move.call(trashed) }.ok?

    [ trashed.id, 0 ].each do |id|
      result = move([ kept.id, id ], folder)

      assert_not result.ok?
      assert_not result.denied?
      assert_equal [ "An image you chose is gone. Nothing was moved." ], result.errors
    end
    assert_nil kept.reload.folder_id
    assert_empty events
  end

  test "a move into a folder deleted first moves nothing and says the folder is gone" do
    folder = Media::Folder.create!(name: "Client A")
    asset = create_media_asset
    assert as_owner { Media::DeleteFolder.call(folder) }.ok?

    result = move([ asset.id ], folder)

    assert_not result.ok?
    assert_equal [ "That folder is gone." ], result.errors
    assert_nil asset.reload.folder_id
    assert_empty events
  end

  test "a move touches neither updated_at nor the content version" do
    folder = Media::Folder.create!(name: "Client A")
    asset = create_media_asset
    updated_at = asset.reload.updated_at
    version = PublicSite.content_version
    bumped = PublicSite::Version.current

    travel 1.minute do
      assert move([ asset.id ], folder).ok?
    end

    assert_equal updated_at, asset.reload.updated_at
    assert_equal bumped, PublicSite::Version.current
    assert_equal version, PublicSite.content_version
  end
end
