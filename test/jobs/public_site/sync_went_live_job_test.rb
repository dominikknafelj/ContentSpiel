require "test_helper"

class PublicSite::SyncWentLiveJobTest < ActiveJob::TestCase
  setup do
    @root = Page.create!(title: "Home", slug: "", published_at: 1.day.ago)
    # Scheduled through the service, so it has a copy that is due at its time.
    @fresh = create_page(title: "Fresh", parent: @root, published: false)
    ContentBlocks::Save.call(ContentBlock.new(owner: @fresh), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } })
    assert Pages::Save.call(@fresh, attributes: { published_at: 1.hour.from_now }).ok?
    blog = Page.create!(parent: @root, title: "Blog", published_at: 1.day.ago)
    blog.content_blocks.create!(block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    @post = Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago)
  end

  test "moves the posts of a listing page that went live since the last run, however long ago, and records no audit event" do
    assert_equal "/blog/hello", @post.full_path("en")
    travel 3.days

    assert_no_difference -> { Audit::Event.count } do
      PublicSite::SyncWentLiveJob.perform_now
    end

    assert_equal "/fresh/hello", @post.full_path("en")
  end

  test "a failure is logged, not raised, so the next run still happens" do
    travel 2.hours
    log = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(log)
    begin
      with_singleton_override(PublicSite::Paths, :refresh, ->(**) { raise "boom" }) do
        assert_nothing_raised { PublicSite::SyncWentLiveJob.perform_now }
      end
    ensure
      Rails.logger = original
    end

    assert_match(/\[public_paths\].*RuntimeError: boom/, log.string)
  end

  test "is scheduled every five minutes wherever the trash sweep is" do
    schedule = YAML.load_file(Rails.root.join("config/recurring.yml"))
    schedule.each do |environment, tasks|
      next unless tasks.key?("trash_purge_expired")

      assert_equal({ "class" => "PublicSite::SyncWentLiveJob", "queue" => "default", "schedule" => "every 5 minutes" },
        tasks["public_paths_sync_went_live"], environment)
    end
  end
end
