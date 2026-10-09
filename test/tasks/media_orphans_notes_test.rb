require "test_helper"
require "rake"
require "support/note_files_helper"

# `media:orphans` is the media library's cleanup: it must never list, let
# alone purge, a blob of the notes' storage service (notes spec §3.6). A
# note's files are removed by the notes services, and a note blob without an
# attachment row is theirs to explain, not a library leftover.
class MediaOrphansNotesTaskTest < ActiveSupport::TestCase
  include NoteFilesHelper

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("media:orphans")
    @library = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("library"), filename: "library-orphan.txt")
    @note = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("note"), filename: "note-orphan.txt", service_name: "notes")
  end

  teardown { ActiveStorage::Blob.service.delete(@library.key) }

  def run_task
    Rake::Task["media:orphans"].reenable
    capture_io { Rake::Task["media:orphans"].invoke }.first
  end

  test "it lists the library's orphan and not a note's" do
    output = run_task

    assert_match "library-orphan.txt", output
    assert_no_match "note-orphan", output
  end

  test "CONFIRM=1 purges the library's orphan and leaves a note's blob and its file" do
    ENV["CONFIRM"] = "1"
    run_task

    assert_not ActiveStorage::Blob.exists?(@library.id)
    assert ActiveStorage::Blob.exists?(@note.id)
    assert stored?(@note.key)
  ensure
    ENV.delete("CONFIRM")
  end
end
