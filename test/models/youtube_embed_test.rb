require "test_helper"

class YoutubeEmbedTest < ActiveSupport::TestCase
  test "video_id is required" do
    embed = YoutubeEmbed.new

    assert_not embed.valid?
    assert_includes embed.errors[:video_id], "can't be blank"
  end

  test "video_id must look like a real YouTube video id" do
    embed = YoutubeEmbed.new(video_id: "not a valid id")

    assert_not embed.valid?
    assert_includes embed.errors[:video_id], "is invalid"
  end

  test "video_id accepts the standard 11-character id shape" do
    embed = YoutubeEmbed.new(video_id: "dQw4w9WgXcQ")

    assert embed.valid?
  end

  test "video_id is unique" do
    YoutubeEmbed.create!(video_id: "dQw4w9WgXcQ")
    duplicate = YoutubeEmbed.new(video_id: "dQw4w9WgXcQ")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:video_id], "has already been taken"
  end

  # -- URL parsing -----------------------------------------------------------

  test "video_id_from_url extracts the id from a watch URL" do
    assert_equal "dQw4w9WgXcQ", YoutubeEmbed.video_id_from_url("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
  end

  test "video_id_from_url extracts the id from a watch URL with extra query params" do
    assert_equal "dQw4w9WgXcQ",
      YoutubeEmbed.video_id_from_url("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=30s&list=PL123")
  end

  test "video_id_from_url extracts the id from a youtu.be short link" do
    assert_equal "dQw4w9WgXcQ", YoutubeEmbed.video_id_from_url("https://youtu.be/dQw4w9WgXcQ")
  end

  test "video_id_from_url extracts the id from a youtu.be short link with a query string" do
    assert_equal "dQw4w9WgXcQ", YoutubeEmbed.video_id_from_url("https://youtu.be/dQw4w9WgXcQ?t=30")
  end

  test "video_id_from_url extracts the id from an embed URL" do
    assert_equal "dQw4w9WgXcQ", YoutubeEmbed.video_id_from_url("https://www.youtube.com/embed/dQw4w9WgXcQ")
  end

  test "video_id_from_url extracts the id from a shorts URL" do
    assert_equal "dQw4w9WgXcQ", YoutubeEmbed.video_id_from_url("https://www.youtube.com/shorts/dQw4w9WgXcQ")
  end

  test "video_id_from_url works without a scheme" do
    assert_equal "dQw4w9WgXcQ", YoutubeEmbed.video_id_from_url("www.youtube.com/watch?v=dQw4w9WgXcQ")
  end

  test "video_id_from_url returns nil for a non-YouTube URL" do
    assert_nil YoutubeEmbed.video_id_from_url("https://example.com/watch?v=dQw4w9WgXcQ")
  end

  test "video_id_from_url returns nil for a YouTube URL with no recognizable video id" do
    assert_nil YoutubeEmbed.video_id_from_url("https://www.youtube.com/")
  end

  test "video_id_from_url returns nil for a blank url" do
    assert_nil YoutubeEmbed.video_id_from_url("")
    assert_nil YoutubeEmbed.video_id_from_url(nil)
  end

  # -- find_or_create_from_url ------------------------------------------------

  test "find_or_create_from_url creates a new record for a URL not seen before" do
    assert_difference "YoutubeEmbed.count", 1 do
      embed = YoutubeEmbed.find_or_create_from_url("https://www.youtube.com/watch?v=dQw4w9WgXcQ")

      assert_equal "dQw4w9WgXcQ", embed.video_id
    end
  end

  test "find_or_create_from_url reuses the existing record for the same video, even from a different URL shape" do
    existing = YoutubeEmbed.create!(video_id: "dQw4w9WgXcQ")

    assert_no_difference "YoutubeEmbed.count" do
      embed = YoutubeEmbed.find_or_create_from_url("https://youtu.be/dQw4w9WgXcQ")

      assert_equal existing, embed
    end
  end

  test "find_or_create_from_url returns nil for a URL that isn't a recognizable YouTube video" do
    assert_no_difference "YoutubeEmbed.count" do
      assert_nil YoutubeEmbed.find_or_create_from_url("https://example.com/not-youtube")
    end
  end

  # -- ActionText::Attachable --------------------------------------------------

  test "is attachable by signed global id" do
    embed = YoutubeEmbed.create!(video_id: "dQw4w9WgXcQ")

    resolved = ActionText::Attachable.from_attachable_sgid(embed.attachable_sgid)

    assert_equal embed, resolved
  end

  test "renders through the youtube_embeds/youtube_embed partial" do
    embed = YoutubeEmbed.new(video_id: "dQw4w9WgXcQ")

    assert_equal "youtube_embeds/youtube_embed", embed.to_partial_path
  end
end
