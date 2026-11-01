require "test_helper"

# Two queues, so a burst of image work never delays a mail, a sweep or a
# purge: `default` for everything, `images` for the jobs that decode and
# encode pictures (and only those), served by a worker of one thread.
class JobQueuesTest < ActiveSupport::TestCase
  IMAGE_JOBS = %w[Media::RenditionJob ActiveStorage::AnalyzeJob ActiveStorage::TransformJob].freeze

  # The app's own jobs, the mail job and Active Storage's: not the gems'
  # background jobs, whose queues are theirs (Solid Queue's, Turbo's).
  def jobs
    Rails.application.eager_load!
    ours = ApplicationJob.descendants
    (ours + ActiveStorage::BaseJob.descendants).select(&:name)
  end

  test "every job of the app is on default or images, and images holds only the image jobs" do
    queues = jobs.to_h { |job| [ job.name, job.new.queue_name ] }

    assert queues.any?
    assert_empty queues.values.uniq - %w[default images], "unexpected queues: #{queues.inspect}"
    assert_equal [], queues.select { |_, queue| queue == "images" }.keys - IMAGE_JOBS
    assert_equal IMAGE_JOBS.sort, IMAGE_JOBS.select { |name| queues[name] == "images" }.sort
    assert_equal %w[images], IMAGE_JOBS.filter_map { |name| queues[name] }.uniq
    assert_equal "default", queues.fetch("ActiveStorage::PurgeJob")
    # Mail takes the mailer's queue, which is unset: Active Job's default.
    assert_nil ApplicationMailer.deliver_later_queue_name
    assert_equal "default", ActiveJob::Base.default_queue_name
  end

  test "the default worker does not take the images queue" do
    config = YAML.safe_load(ERB.new(File.read(Rails.root.join("config/queue.yml"))).result, aliases: true).fetch("production")
    workers = config.fetch("workers")

    assert workers.none? { |worker| worker["queues"].to_s.include?("*") }
    default = workers.find { |worker| worker["queues"] == "default" }
    images = workers.find { |worker| worker["queues"] == "images" }
    assert default && images
    assert_equal 3, default["threads"]
    assert_equal 1, images["threads"]
    assert_equal 1, images["processes"]
  end
end
