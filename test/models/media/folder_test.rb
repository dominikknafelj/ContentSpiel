require "test_helper"

class Media::FolderTest < ActiveSupport::TestCase
  test "a name is stripped, required, at most 80 characters and holds no control character" do
    assert_equal "Trips", Media::Folder.create!(name: "  Trips  ").name

    blank = Media::Folder.new(name: "   ")
    assert_not blank.valid?
    assert_includes blank.errors[:name], "Give the folder a name."

    assert Media::Folder.new(name: "a" * 80).valid?
    long = Media::Folder.new(name: "a" * 81)
    assert_not long.valid?
    assert_includes long.errors[:name], "Use at most 80 characters."

    assert_not Media::Folder.new(name: "bad\u0007name").valid?
    assert_not Media::Folder.new(name: "two\nlines").valid?
  end

  test "two folders of one parent may not share a name in any case, and two at the top neither" do
    now = Time.current
    row = ->(name, parent_id) { { name: name, parent_id: parent_id, created_at: now, updated_at: now } }
    # A failed statement aborts the test's transaction; a savepoint keeps it usable.
    refused = ->(name, parent_id) do
      assert_raises(ActiveRecord::RecordNotUnique) do
        Media::Folder.transaction(requires_new: true) { Media::Folder.insert_all!([ row.(name, parent_id) ]) }
      end
    end

    Media::Folder.insert_all!([ row.("Trips", nil) ])
    refused.("TRIPS", nil)

    parent = Media::Folder.create!(name: "Parent")
    Media::Folder.insert_all!([ row.("Trips", parent.id) ])
    refused.("trips", parent.id)
  end

  test "deleting a folder around the services leaves its images in no folder" do
    folder = Media::Folder.create!(name: "Trips")
    asset = Media::Asset.new(folder: folder)
    asset.file.attach(io: File.open(file_fixture("tiny.png")), filename: "tiny.png", content_type: "image/png")
    assert asset.save, asset.errors.full_messages.to_sentence
    assert_equal folder.id, asset.reload.folder_id

    folder.delete

    assert_nil asset.reload.folder_id
  end
end
