require "test_helper"

# The endpoint the Trix editor's paste handler calls to turn a pasted YouTube
# URL into an attachable it can insert (design spec section 8) -- gated by the
# same session auth as every other /avo route, since it's part of the admin,
# not the public site.
class YoutubeEmbedsTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "editor@example.com", password: "password123")
  end

  test "an unauthenticated request cannot create a youtube embed" do
    post "/avo/youtube_embeds", params: { url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ" }

    assert_response :redirect
    assert_equal 0, YoutubeEmbed.count
  end

  test "a valid YouTube URL creates the embed and returns its sgid" do
    sign_in_as(@user)

    assert_difference "YoutubeEmbed.count", 1 do
      post "/avo/youtube_embeds", params: { url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ" }
    end

    assert_response :success
    embed = YoutubeEmbed.find_by!(video_id: "dQw4w9WgXcQ")
    assert_equal embed.attachable_sgid, response.parsed_body["sgid"]
  end

  test "the same video pasted twice reuses the same embed and sgid" do
    sign_in_as(@user)
    first_sgid = nil

    assert_difference "YoutubeEmbed.count", 1 do
      post "/avo/youtube_embeds", params: { url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ" }
      first_sgid = response.parsed_body["sgid"]
    end

    assert_no_difference "YoutubeEmbed.count" do
      post "/avo/youtube_embeds", params: { url: "https://youtu.be/dQw4w9WgXcQ" }
    end

    assert_response :success
    assert_equal first_sgid, response.parsed_body["sgid"]
  end

  test "a URL that isn't a recognizable YouTube video is rejected" do
    sign_in_as(@user)

    assert_no_difference "YoutubeEmbed.count" do
      post "/avo/youtube_embeds", params: { url: "https://example.com/not-a-video" }
    end

    assert_response :unprocessable_entity
    assert response.parsed_body["error"].present?
  end

  # Trix's own vendored HTML sanitizer strips <iframe> from attachment
  # content shown in the editable area unconditionally -- there is no public
  # config to widen it, unlike ActionText::ContentHelper's server-side one
  # (config/initializers/action_text.rb). The real embed renders correctly on
  # the public page (PagesRoutingTest covers that); this is what Avo's own
  # Post edit form has to render instead.
  test "a post's edit form shows a thumbnail for an attached embed, not a stripped iframe" do
    sign_in_as(@user)
    embed = YoutubeEmbed.create!(video_id: "dQw4w9WgXcQ")
    body = %(<p>Intro</p><action-text-attachment sgid="#{embed.attachable_sgid}"></action-text-attachment>)
    post_record = Post.create!(content_type: :blog, title: "Has An Embed", body: body)

    get "/avo/resources/posts/#{post_record.id}/edit"

    assert_response :success
    assert_includes response.body, "img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg"
    assert_not_includes response.body, "<iframe"
  end
end
