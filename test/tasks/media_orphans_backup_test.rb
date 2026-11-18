require "test_helper"
require "rake"

# `media:orphans` walks blob rows and never the disk, so the backup's status
# file, which lives in the files volume beside the blobs, is never a leftover
# to it.
class MediaOrphansBackupTest < ActiveSupport::TestCase
  setup { Rails.application.load_tasks unless Rake::Task.task_defined?("media:orphans") }

  test "media:orphans never touches the backup folder" do
    status = Rails.root.join("tmp/storage/backup/status.json")
    FileUtils.mkdir_p(status.dirname)
    File.write(status, "{}")
    ENV["CONFIRM"] = "1"

    Rake::Task["media:orphans"].reenable
    capture_io { Rake::Task["media:orphans"].invoke }

    assert File.exist?(status)
  ensure
    ENV.delete("CONFIRM")
    FileUtils.rm_f(status)
  end
end
