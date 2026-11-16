require "test_helper"
require_relative "../support/source_code"

# A library image's folder (`media_assets.folder_id`) has few writers, each
# of which takes the folder's row lock in the order `Media::DeleteFolder`
# relies on and records what it moved (docs/reference/media.md): the move
# (`Media::MoveImages`), the folder's delete (its images go up a level) and
# the upload (an image enters in a folder). A write from anywhere else would
# skip the lock, so a delete racing it could leave an image to the foreign
# key's nullify, and would leave no `media.moved` behind it.
#
# The guard reads `app/` and `lib/` with comments stripped, for an assignment
# of `folder_id` or `folder`, a bulk write or an update that names `folder_id`,
# and a new image built with a folder. It does not read a write that computes
# the column's name, raw SQL, `db/` (the migration) or `app/javascript`.
class MediaFolderWritersTest < ActiveSupport::TestCase
  ROOTS = %w[app lib].freeze

  ALLOWED = %w[app/services/media/move_images.rb app/services/media/delete_folder.rb app/services/media/upload.rb].freeze

  WRITES = [
    /\bfolder_id\s*=(?![=~>])/,
    /\.folder\s*=(?![=~])/,
    /\b(?:update_all|update!?|update_columns?|assign_attributes|insert_all!?|upsert_all?)\(.*\bfolder_id\b/,
    /Asset\b.*\b(?:new|create!?|build|find_or_create_by!?)\(.*\bfolder(?:_id)?:/
  ].freeze

  def offences
    ROOTS.flat_map { |root| Dir[Rails.root.join(root, "**/*.{rb,rake,erb}")] }.flat_map do |path|
      relative = Pathname(path).relative_path_from(Rails.root).to_s
      SourceCode.code_of(path).lines.each_with_index.filter_map do |line, index|
        "#{relative}:#{index + 1}: #{line.strip}" if WRITES.any? { |pattern| line.match?(pattern) }
      end
    end
  end

  test "folder_id is written only by the folder services, the upload and the migration" do
    stray = offences.reject { |offence| ALLOWED.any? { |file| offence.start_with?("#{file}:") } }

    assert_empty stray, "an image's folder is written by Media::MoveImages, Media::DeleteFolder and Media::Upload alone:\n#{stray.join("\n")}"
  end

  test "the guard sees the two writers that exist" do
    written = offences.map { |offence| offence.split(":").first }.uniq

    assert_includes written, "app/services/media/move_images.rb"
    assert_includes written, "app/services/media/delete_folder.rb"
  end

  test "every allowed file writes folder_id" do
    written = offences.map { |offence| offence.split(":").first }.uniq

    assert_empty ALLOWED - written, "a file the guard allows that writes no folder_id is a stale entry"
  end

  test "the guard's patterns read a write and let a read through" do
    assert(WRITES.any? { |pattern| "asset.folder_id = 4".match?(pattern) })
    assert(WRITES.any? { |pattern| "asset.update_columns(folder_id: 4)".match?(pattern) })
    assert(WRITES.any? { |pattern| "Media::Asset.new(folder: folder)".match?(pattern) })
    assert(WRITES.none? { |pattern| "Media::Asset.where(folder_id: 4).count".match?(pattern) })
    assert(WRITES.none? { |pattern| "Route.new(:admin_media_path, [], { folder: 4 })".match?(pattern) })
  end
end
