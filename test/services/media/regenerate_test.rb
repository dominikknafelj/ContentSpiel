require "test_helper"

class Media::RegenerateTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def upload(filename = "wide.png")
    asset = nil
    perform_enqueued_jobs(only: ActiveStorage::AnalyzeJob) { asset = create_media_asset(filename: filename) }
    clear_enqueued_jobs
    asset
  end

  def made(asset)
    Media::RenditionJob.perform_now(asset)
    asset.reload
  end

  test "it enqueues each stale or preview-less kept image once, audits the count, and touches no trashed image" do
    current = made(upload("wide.png"))
    stale = made(upload("medium.png"))
    stale.update_columns(renditions_fingerprint: "older") # version: none (a test records an older generation)
    previewless = made(upload("tiny.png"))
    previewless.update_columns(preview: nil) # version: none (a test removes the preview)
    trashed = upload("small.gif")
    trashed.update_columns(trashed_at: Time.current) # version: none (a test trashes the image)
    clear_enqueued_jobs

    result = nil
    assert_enqueued_jobs 2, only: Media::RenditionJob do
      result = Media::Regenerate.call(actor: nil)
    end

    assert result.ok?
    assert_equal 2, result.record
    queued = enqueued_jobs.map { |job| ActiveJob::Arguments.deserialize(job["arguments"]).first }
    assert_equal [ stale, previewless ].sort_by(&:id), queued.sort_by(&:id)
    assert_not_includes queued, current
    assert_not_includes queued, trashed
    assert(enqueued_jobs.all? { |job| job["queue_name"] == "images" && job["job_class"] == "Media::RenditionJob" })

    event = Audit::Event.find_by!(action: "media.regenerated")
    assert_equal 2, event.metadata["count"]
    assert_equal Current.site, event.subject
  end

  test "a second press while the jobs are queued makes each image once" do
    asset = upload("wide.png")
    Media::Regenerate.call(actor: nil)
    Media::Regenerate.call(actor: nil)
    assert_enqueued_jobs 2, only: Media::RenditionJob

    assert_difference -> { ActiveStorage::VariantRecord.where(blob_id: asset.file.blob.id).count }, 4 do
      perform_enqueued_jobs(only: Media::RenditionJob)
    end
    assert_equal ImageSettings.current.fingerprint, asset.reload.renditions_fingerprint
  end

  test "without settings.manage it is denied, queues nothing and audits the refusal" do
    upload("wide.png")
    clear_enqueued_jobs

    result = as(users(:editor_branch)) { Media::Regenerate.call }

    assert result.denied?
    assert_no_enqueued_jobs(only: Media::RenditionJob)
    assert Audit::Event.exists?(action: "access.denied")
    assert_not Audit::Event.exists?(action: "media.regenerated")
  end

  test "with nothing to make it succeeds with zero and queues nothing" do
    Media::Asset.delete_all
    result = Media::Regenerate.call(actor: nil)

    assert result.ok?
    assert_equal 0, result.record
    assert_no_enqueued_jobs(only: Media::RenditionJob)
  end
end
