# One uploaded image (design spec §4.2), backing a rich-text `image` node's
# `asset_id` (`RichText::BuiltIns`, `RichText::Schema`'s `image` node
# attribute). Kept while referenced, with no automatic cleanup of orphaned
# rows yet -- an interim state (global constraints, docs/roadmap.md) closed
# by the media library sub-project.
#
# Deliberately not the same model an `image` *content block*'s own `image`
# attachment uses (`ContentBlock#image`, an open type) -- design spec §4.2's
# "Relation to open types": unifying the two storage paths is that same
# future sub-project's job, not this one's.
class MediaAsset < ApplicationRecord
  # Exactly png/jpeg/gif/webp (global constraints) -- no SVG (an SVG's
  # "image" bytes are actually executable markup: inline `<script>`, and
  # external resource loads a browser will happily follow) and nothing else,
  # regardless of what a client's Content-Type header or filename claims.
  ALLOWED_CONTENT_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze

  MAX_BYTE_SIZE = 10.megabytes

  belongs_to :created_by, class_name: "User", optional: true

  has_one_attached :file

  validate :file_is_attached
  validate :image_type_and_size, if: -> { file.attached? }

  # Cache the *validated* content type/size onto their own columns right
  # before a valid record is written -- never in a `before_validation`,
  # which would let this stomp whatever `image_type_and_size` is about to
  # check against with a value nobody has verified yet. Reading these back
  # off the record (a listing, this upload's own JSON response) is then a
  # plain column read, not a re-open of the blob to re-sniff bytes that
  # were already sniffed once, at save time, for the validation this
  # callback is piggybacking on.
  before_save :cache_metadata_from_file, if: -> { file.attached? }

  # The public URL an `image` node's `html` render (`RichText::BuiltIns`)
  # points an `<img>` at -- `rails_blob_path`, not `rails_blob_url`: this is
  # embedded inside a page's own HTML, which already carries its own host,
  # same reasoning `PublicSite::Urls` gives for every other in-page link
  # being a path, not a full URL.
  def url
    return nil unless file.attached?

    Rails.application.routes.url_helpers.rails_blob_path(file, only_path: true)
  end

  private

  def file_is_attached
    errors.add(:file, "must be attached") unless file.attached?
  end

  # The one rule design spec §4.2 states (global constraints: "png/jpeg/gif/
  # webp only, max 10 MB") -- checked against the blob's *actual* bytes, not
  # whatever the upload's own Content-Type header or filename claimed (see
  # `#sniffed_content_type`'s own comment: that's exactly the pair an
  # attacker controls, and exactly the pair Marcel's own sniffing falls back
  # to *trusting* when asked to guess from a name/declared type it hasn't
  # ruled out with real magic bytes).
  def image_type_and_size
    errors.add(:file, "must be 10 MB or smaller") if file.blob.byte_size > MAX_BYTE_SIZE
    errors.add(:file, "must be a PNG, JPEG, GIF, or WEBP image") unless ALLOWED_CONTENT_TYPES.include?(sniffed_content_type)
  end

  # `Marcel::MimeType.for(io)`, called with neither `:name` nor
  # `:declared_type` -- both of those are exactly the attacker-controlled
  # metadata this check exists to *not* trust (a renamed `evil.png` sent
  # with `Content-Type: image/png`, per the plan's own rule), and Marcel's
  # own fallback behavior, given either, is to trust it the moment content
  # sniffing alone doesn't produce a confident match rather than to keep
  # looking at the bytes. Called with only the raw content, Marcel can only
  # ever answer from the bytes themselves -- a real image's magic-byte
  # signature, or `application/octet-stream` for anything else -- which is
  # the one answer this validation is willing to trust.
  #
  # `#attachable_io`, not `file.blob.open`/`file.blob.download`: a `validate`
  # runs *before* Active Storage's own `after_commit` upload hook fires (see
  # that method's own comment), so a brand-new, not-yet-saved attachment's
  # blob has nothing on the storage service yet for `blob.open` to find --
  # only the in-memory io this record was actually handed still does.
  #
  # Memoized: `image_type_and_size` and `#cache_metadata_from_file` both
  # want this same value for the same validated attachment, and neither
  # should re-read the underlying io to ask twice.
  def sniffed_content_type
    @sniffed_content_type ||= with_attachable_io { |io| Marcel::MimeType.for(io) }
  end

  # Yields the raw io behind this record's `file` attachment to the block,
  # from whichever of the two places it currently lives.
  #
  # While the attachment is still pending -- assigned via `file.attach(...)`
  # but not yet uploaded to the storage service, which is the case for
  # *any* record `validate` runs against, new or persisted, since Active
  # Storage only uploads from an `after_commit` hook that fires strictly
  # after every `validate` (see below) -- `record.attachment_changes[name]`
  # is Active Storage's own (`:nodoc:`, but public) handle on it, and
  # `Attached::Changes::CreateOne#attachable` is exactly the `io:`/
  # `filename:`/`content_type:` Hash (or `ActionDispatch::Http
  # ::UploadedFile`) this attachment was actually given -- the same object
  # `unfurl` already read once, for the blob's own checksum/byte_size, and
  # rewound back to position 0 (`ActiveStorage::Blob#compute_checksum_in_
  # chunks`'s own final `io.rewind`), so reading it again here for a
  # second, independent sniff is exactly as safe as Active Storage's own
  # eventual upload reading it a third time once this record is actually
  # saved.
  #
  # Once the attachment *has* been uploaded (a persisted `MediaAsset`,
  # freshly reloaded and re-validated), `attachment_changes` no longer
  # holds anything for it -- Active Storage clears the pending change the
  # moment its `after_commit` upload runs -- so this falls back to
  # `blob.open`, which by then has real bytes on the service to open.
  def with_attachable_io(&block)
    change = attachment_changes["file"]
    return file.blob.open(&block) if change.nil?

    attachable = change.attachable
    io = attachable.is_a?(Hash) ? attachable[:io] : attachable.open
    block.call(io)
  end

  # `width`/`height` come from the blob's own `metadata`, written by
  # `file.analyze` (design spec §4.2's "Implement" step) -- but *not* by
  # this callback: `Admin::MediaAssetsController#analyze_dimensions` calls
  # `analyze` (and writes these two columns) in a second pass, strictly
  # after this record's own save has actually committed and Active
  # Storage's own `after_commit` hook has uploaded the blob's bytes --
  # analysis needs the real file on the storage service, which isn't there
  # yet at `before_save` time (`#with_attachable_io`'s own comment). So
  # this callback leaves both nil on every ordinary save; that's fine,
  # neither is a NOT NULL column, and `RichText::ImageComponent`'s own
  # `<img>` render never reads either.
  def cache_metadata_from_file
    self.byte_size = file.blob.byte_size
    self.content_type = sniffed_content_type

    # Merged onto whatever's already there, not overwritten outright: a
    # second save of an already-analyzed asset (nothing about this model
    # re-attaches a file after the fact today, but nothing rules it out
    # later either) must not blank out real `width`/`height` this callback
    # itself has no way to recompute yet.
    metadata = file.blob.metadata || {}
    self.width = metadata["width"] if metadata.key?("width")
    self.height = metadata["height"] if metadata.key?("height")
  end
end
