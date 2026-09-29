require "test_helper"
require "rake"

# `media:variants` (Task 10's own controller ruling, `lib/tasks/media.rake`):
# the catch-up for a preprocessed image variant that never got processed --
# a failed/lost `TransformJob`, or an asset attached before all four widths
# existed. It only ever looks at whether an `ActiveStorage::VariantRecord`
# exists, never at whether a job happens to be queued, so it's exercised
# here with `ActiveJob::TestHelper#clear_enqueued_jobs` standing in for
# "the upload-time jobs never ran" -- the same end state a genuinely failed
# job would leave behind.
class MediaVariantsTaskTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("media:variants")
    @task = Rake::Task["media:variants"]
    @task.reenable
  end

  # `wide.png` (test/fixtures/files) is a real 3000x2000 PNG, same fixture
  # `Media::AssetTest` uses for "all four widths eventually process" --
  # every declared variant width is smaller than that, so all four are
  # missing until processed.
  test "enqueues every missing variant for a non-GIF asset, then finds nothing left to enqueue" do
    asset = Media::Asset.new
    asset.file.attach(io: File.open(file_fixture("wide.png")), filename: "wide.png", content_type: "image/png")
    asset.save!
    analyze(asset)

    # Stand in for "the upload-time preprocessing jobs never ran" (a queue
    # outage, a worker that crashed) -- no VariantRecord exists for any of
    # the four widths yet.
    clear_enqueued_jobs

    output = capture_io { @task.invoke }.first
    assert_match(/media:variants: enqueued 4 variant job\(s\)/, output)
    assert_equal 4, transform_jobs.size

    perform_enqueued_jobs
    assert_equal [ 480, 960, 1600, 2400 ], asset.reload.srcset.map(&:last)

    @task.reenable
    again = capture_io { @task.invoke }.first
    assert_match(/media:variants: enqueued 0 variant job\(s\)/, again)
    assert_empty transform_jobs
  end

  test "re-enqueues only the still-missing widths, not ones already processed" do
    asset = Media::Asset.new
    asset.file.attach(io: File.open(file_fixture("wide.png")), filename: "wide.png", content_type: "image/png")
    asset.save!
    analyze(asset)
    perform_enqueued_jobs
    assert_equal [ 480, 960, 1600, 2400 ], asset.reload.srcset.map(&:last)

    # Simulate one variant's record having been lost (never actually
    # happens through the app itself, but a restored backup or a direct
    # SQL edit could leave exactly this state) -- everything else stays
    # processed.
    asset.file.blob.variant_records.find_by!(variation_digest: asset.file.variant(:w960).variation.digest).destroy!

    output = capture_io { @task.invoke }.first
    assert_match(/media:variants: enqueued 1 variant job\(s\)/, output)
    assert_equal 1, transform_jobs.size

    perform_enqueued_jobs
    assert_equal [ 480, 960, 1600, 2400 ], asset.reload.srcset.map(&:last)
  end

  test "never enqueues anything for a GIF, which gets no variants at all" do
    asset = Media::Asset.new
    asset.file.attach(io: File.open(file_fixture("small.gif")), filename: "small.gif", content_type: "image/gif")
    asset.save!
    analyze(asset)
    clear_enqueued_jobs

    output = capture_io { @task.invoke }.first
    assert_match(/media:variants: enqueued 0 variant job\(s\)/, output)
    assert_empty transform_jobs
  end

  private

  # Scoped to `TransformJob` alone: performing a variant's own transform
  # incidentally enqueues an `ActiveStorage::AnalyzeJob` for the *new* blob
  # that variant's processed image gets attached to (ordinary Active
  # Storage behaviour, nothing this rake task does), which would otherwise
  # show up as unrelated noise in an `enqueued_jobs`/`assert_empty` check.
  def transform_jobs
    enqueued_jobs.select { |job| job["job_class"] == "ActiveStorage::TransformJob" }
  end

  # Mirrors `Media::Upload#analyze_dimensions` (and `Media::AssetTest`'s own
  # private helper of the same name): `file.analyze` needs the blob's real
  # bytes on the storage service, which only exist once this record's save
  # has actually committed.
  def analyze(asset)
    asset.file.analyze
    metadata = asset.file.blob.metadata || {}
    asset.update_columns(width: metadata["width"], height: metadata["height"])
  end
end
