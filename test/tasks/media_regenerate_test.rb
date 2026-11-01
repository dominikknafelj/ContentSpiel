require "test_helper"
require "rake"

# `bin/rails media:regenerate` queues every kept image that is not made with
# the current settings, judged by what is recorded on the row, never by what
# is queued: running it twice queues the stale images twice, and the job makes
# each once.
class MediaRegenerateTaskTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup { Rails.application.load_tasks unless Rake::Task.task_defined?("media:regenerate") }

  def run_task
    Rake::Task["media:regenerate"].reenable
    capture_io { Rake::Task["media:regenerate"].invoke }.first
  end

  test "media:regenerate enqueues the stale images once and nothing for a made one" do
    made = make_renditions!(create_media_asset(filename: "medium.png"))
    stale = make_renditions!(create_media_asset(filename: "medium.png"), widths: [ 480 ], fingerprint: "adopted")
    never = create_media_asset(filename: "tiny.png")
    trashed = create_media_asset(filename: "tiny.png")
    trashed.update_columns(trashed_at: Time.current) # version: none (a test puts an image in the trash)
    clear_enqueued_jobs

    output = run_task

    queued = enqueued_jobs.select { |job| job["job_class"] == "Media::RenditionJob" }.map { |job| job["arguments"].first["_aj_globalid"] }
    assert_equal [ stale, never ].map { |asset| asset.to_global_id.to_s }.sort, queued.sort
    assert_not_includes queued, made.to_global_id.to_s
    assert_match "media:regenerate: 2 image(s) queued", output
  end
end
