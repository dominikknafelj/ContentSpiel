require "test_helper"

class PublishableTest < ActiveSupport::TestCase
  test "status follows published_at" do
    assert_equal "draft", Post.new(published_at: nil).status
    assert_equal "scheduled", Post.new(published_at: 1.day.from_now).status
    assert_equal "live", Post.new(published_at: 1.minute.ago).status
    assert_equal "live", Page.new(published_at: 1.minute.ago).status
  end

  test "publish_now! and unpublish! set and clear published_at" do
    post = Post.create!(content_type: :blog, title: "Draft")
    post.publish_now!
    assert post.reload.live?

    post.unpublish!
    assert_equal "draft", post.reload.status
  end

  test "listed_posts includes unpublished posts only when asked" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    block = root.content_blocks.create!(block_type: :post_list, position: 0)
    scheduled = Post.create!(content_type: :blog, title: "Soon", published_at: 1.day.from_now)

    assert_not_includes block.listed_posts, scheduled
    assert_includes block.listed_posts(include_unpublished: true), scheduled
  end


  # `scheduled` is strictly later than now: with `published` it splits the
  # records that have a time, and a draft (NULL) is in neither.
  test "scheduled holds exactly the records with a future time" do
    freeze_time do
      draft = Post.create!(content_type: :blog, title: "Draft")
      future = Post.create!(content_type: :blog, title: "Soon", published_at: 1.second.from_now)
      now = Post.create!(content_type: :blog, title: "Now", published_at: Time.current)
      past = Post.create!(content_type: :blog, title: "Live", published_at: 1.day.ago)

      assert_equal [ future ], Post.scheduled.to_a
      assert_equal [ now, past ].sort_by(&:id), Post.published.order(:id).to_a
      assert_not_includes Post.scheduled.or(Post.published), draft
      assert_equal "scheduled", future.status
      assert_equal "live", now.status
    end
  end

  test "scheduled compares in UTC whatever the zone, and composes with a narrowed relation" do
    soon = Post.create!(content_type: :blog, title: "Soon", published_at: 30.minutes.from_now)
    Post.create!(content_type: :blog, title: "Just live", published_at: 30.minutes.ago)

    # In a zone hours away from UTC a comparison made on local wall-clock time
    # would move either post across the line.
    %w[Pacific/Auckland America/Los_Angeles].each do |zone|
      Time.use_zone(zone) { assert_equal [ soon ], Post.kept.scheduled.to_a, zone }
    end
    assert_empty Post.where.not(id: soon.id).scheduled
    assert_match(/"posts"\."published_at" > '/, Post.scheduled.to_sql)
  end
end
