# A YouTube video pasted into a rich text body (design spec section 8),
# resolved by signed global id like any other ActionText::Attachable --
# `include ActionText::Attachable` is what makes `attachable_sgid` and
# `ActionText::Attachable.from_attachable_sgid` work.
#
# One row per distinct video, not one per paste: `find_or_create_from_url`
# reuses an existing row so the same video pasted into two posts still
# resolves through one record.
class YoutubeEmbed < ApplicationRecord
  include ActionText::Attachable

  # youtube.com/watch?v=, youtu.be/, youtube.com/embed/ and
  # youtube.com/shorts/ URLs are all seen in the wild for the same video, so
  # every editor sees is normalized down to this one 11-character id before
  # it ever reaches the database -- a real YouTube id is always exactly this
  # shape (base64url-ish: letters, digits, `-`/`_`).
  VIDEO_ID_PATTERN = /\A[\w-]{11}\z/

  # Matches the id out of any of the URL shapes above, wherever it falls in
  # the path or query string -- one pattern rather than one branch per host,
  # since all four just differ in what comes before the id.
  URL_VIDEO_ID_PATTERN = %r{
    (?:youtube(?:-nocookie)?\.com/(?:watch\?(?:.*&)?v=|embed/|shorts/)|youtu\.be/)
    (?<video_id>[\w-]{11})
  }x

  validates :video_id, presence: true, format: { with: VIDEO_ID_PATTERN }, uniqueness: true

  # The id inside a pasted URL, in whatever shape it was pasted -- or nil if
  # the URL isn't a YouTube video URL this app recognizes at all.
  def self.video_id_from_url(url)
    url.to_s[URL_VIDEO_ID_PATTERN, :video_id]
  end

  # Finds the existing row for this video, or creates it -- nil rather than a
  # validation error for a URL this app doesn't recognize as YouTube, since
  # "not a YouTube URL" isn't a data problem for the attachable record to
  # report, it's the caller's cue not to create an attachment at all.
  def self.find_or_create_from_url(url)
    video_id = video_id_from_url(url)
    return nil if video_id.nil?

    find_or_create_by!(video_id: video_id)
  end

  # The partial rendering the real embed -- used for the public page, and for
  # Avo's editor preview too, except that Trix's own vendored HTML sanitizer
  # (a separate pass from ActionText::ContentHelper's, with no public config
  # to widen it) unconditionally strips <iframe>/<script>/<form>/<noscript>
  # from attachment content shown in the editable area, so it never actually
  # reaches the DOM there -- see #to_trix_content_attachment_partial_path.
  def to_partial_path
    "youtube_embeds/youtube_embed"
  end

  # A static thumbnail instead of the real iframe (see #to_partial_path):
  # Trix would silently strip the iframe out and leave a blank box. YouTube
  # serves a thumbnail for every public video at this URL with no API key.
  def to_trix_content_attachment_partial_path
    "youtube_embeds/trix_preview"
  end
end
