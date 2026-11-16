require "test_helper"

# `Media::LibrarySignals` (media-folders spec §11): one stream for the whole
# library, one signal per folder write or move, sent after the commit, naming
# nothing.
class Media::LibrarySignalsTest < ActiveSupport::TestCase
  TAB = "tab-12345678".freeze

  def sent = broadcasts(Media::LibrarySignals::STREAM).map { |payload| ActiveSupport::JSON.decode(payload) }

  def as_editor(&) = as(users(:one), &)

  test "a folder write and a move each send one library signal after the commit and none on a rollback" do
    folder = nil
    assert_difference -> { sent.size }, 1 do
      folder = as_editor { Media::SaveFolder.call(attributes: { name: "Trips" }) }.record
    end
    assert_equal({ "kind" => "library", "reason" => "folders" }, sent.last)

    asset = create_media_asset
    assert_difference -> { sent.size }, 1 do
      as_editor { Media::MoveImages.call(asset_ids: [ asset.id ], folder: folder) }
    end
    assert_equal "moved", sent.last["reason"]

    assert_difference -> { sent.size }, 1 do
      assert as_editor { Media::DeleteFolder.call(folder) }.ok?
    end
    assert_equal "folders", sent.last["reason"]

    # Nothing on a refusal, a move that moved nothing, or a rollback.
    assert_no_difference -> { sent.size } do
      assert_not as_editor { Media::SaveFolder.call(attributes: { name: "" }) }.ok?
      assert as_editor { Media::MoveImages.call(asset_ids: [ asset.id ], folder: nil) }.ok?
      ActiveRecord::Base.transaction do
        Media::LibrarySignals.changed(reason: "folders")
        raise ActiveRecord::Rollback
      end
    end
  end

  test "the signal is sent only once the outermost transaction commits" do
    ActiveRecord::Base.transaction do
      Media::LibrarySignals.changed(reason: "folders")
      assert_empty sent
    end
  end

  test "the signal names no folder, image or word" do
    Media::LibrarySignals.changed(reason: "folders")
    assert_equal [ %w[kind reason] ], sent.map { |payload| payload.keys.sort }

    Current.set(notes_tab: TAB) { Media::LibrarySignals.changed(reason: "moved") }
    assert_equal %w[kind origin reason], sent.last.keys.sort
    assert_equal TAB, sent.last["origin"]

    assert_raises(ArgumentError) { Media::LibrarySignals.changed(reason: "a whole sentence") }
  end
end
