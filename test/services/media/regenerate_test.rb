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

  # The job reads the settings when it RUNS. Two presses queue the image
  # twice; the settings are then changed and saved; the first job makes the
  # image once, with the NEW widths and format, and the second finds it made
  # and does nothing. Counted by the work done (a width transformed, the
  # generation written), never by variant records, which Active Storage
  # finds again instead of making twice.
  test "two presses, then new settings saved before the jobs run: each image is made once, with the new settings only" do
    asset = upload("wide.png")
    old_fingerprint = ImageSettings.current.fingerprint
    2.times { assert Media::Regenerate.call(actor: nil).ok? }
    assert_enqueued_jobs 2, only: Media::RenditionJob

    SiteSetting.instance.update!(image_widths: [ 300, 700 ], image_quality_webp: 40)
    Current.reset
    new_fingerprint = ImageSettings.current.fingerprint
    assert_not_equal old_fingerprint, new_fingerprint

    widths_made = []
    original = Media::Renditions.method(:transformations)
    statements = capture_sql do
      with_singleton_override(Media::Renditions, :transformations, ->(**args) { widths_made << args[:width]; original.call(**args) }) do
        perform_enqueued_jobs(only: Media::RenditionJob)
      end
    end

    assert_equal [ 300, 700 ], widths_made, "each new width transformed once; none of the old ones; nothing twice"
    assert_equal 1, statements.count { |sql| sql.include?('UPDATE "media_assets"') && sql.include?('"renditions" =') }, "the generation is written once"
    asset.reload
    assert_equal new_fingerprint, asset.renditions_fingerprint
    assert_equal [ 300, 700 ], asset.generation.widths
    assert_equal new_fingerprint, asset.generation.fingerprint
    assert_nil asset.renditions["previous"]
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
