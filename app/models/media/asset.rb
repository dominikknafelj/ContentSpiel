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
class Media::Asset < ApplicationRecord
  extend Mobility

  # Zeitwerk infers a namespaced model's table name by demodulizing it
  # (`Media::Asset` -> `assets`), so this has to be explicit: Task 1 (media
  # library sub-project) renamed the bare `MediaAsset` to `Media::Asset` for
  # the constant alone, keeping the existing `media_assets` table (global
  # constraints: "the table `media_assets` is unchanged") -- the data, and
  # every foreign key/polymorphic `record_type`/`subject_type` string that
  # already points at that table, are untouched by a Ruby-side rename.
  self.table_name = "media_assets"

  # Exactly png/jpeg/gif/webp (global constraints) -- no SVG (an SVG's
  # "image" bytes are actually executable markup: inline `<script>`, and
  # external resource loads a browser will happily follow) and nothing else,
  # regardless of what a client's Content-Type header or filename claims.
  ALLOWED_CONTENT_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze

  MAX_BYTE_SIZE = 10.megabytes

  # The exact responsive widths this app ever serves (global constraints:
  # "Variant names are exactly w480, w960, w1600 and w2400"). Doubles as
  # both the variant *name* Active Storage keys each transformation under
  # (the `has_one_attached` block below, `#srcset`'s own `file.variant
  # (name)`) and the target width `#srcset` compares against the original
  # to decide whether that variant would ever upscale.
  VARIANT_WIDTHS = { w480: 480, w960: 960, w1600: 1600, w2400: 2400 }.freeze

  # This asset's own translated defaults for alt text and caption -- jsonb,
  # same shape and backend as every other translated attribute in this app
  # (config/initializers/mobility.rb). A *placement* (a rich-text image
  # node, an image content block) can still override either of these per
  # use, which is exactly what `#alt_text`/`#caption_text` below resolve --
  # reading `alt`/`caption` directly only ever gets this asset's own literal
  # default in the ambient locale, never an override or a cross-locale
  # fallback.
  translates :alt, :caption

  belongs_to :created_by, class_name: "User", optional: true

  has_one_attached :file do |attachable|
    # Every responsive width the public site can ever ask for, preprocessed
    # right after upload (`preprocessed: true` enqueues one `ActiveStorage
    # ::TransformJob` per variant as soon as this attachment's blob finishes
    # uploading) so a variant is normally already sitting on the storage
    # service by the time a page first requests it -- but never something a
    # page *waits* on: `#srcset` below only ever lists a variant Active
    # Storage has already finished (`Variant#processed?`), so a slow,
    # still-queued or failed job just means fewer `srcset` entries for this
    # request, never a request that blocks on -- or 500s over -- one.
    #
    # Declared unconditionally for every attached file: this block-form DSL
    # only lets a variant be conditioned on its *name*, not on the
    # attachment's own content type, so a GIF gets these same `w480`..
    # `w2400` WebP names declared (and, wastefully, preprocessed) too.
    # `#srcset`/`#variable_image?` are what actually keep a GIF from ever
    # showing one (global constraints: "GIFs get no variants") -- resized
    # WebP stills would throw away the one thing a GIF has that a still
    # image doesn't, its animation.
    VARIANT_WIDTHS.each do |name, target_width|
      attachable.variant name, resize_to_limit: [ target_width, nil ], format: :webp, preprocessed: true
    end
  end

  before_validation :set_default_title

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

  # An `<img src>` always points at the original -- whatever `#srcset`
  # comes back with (including empty, Review Focus 3: a page never fails
  # to render just because every variant is missing, slow, or broken) is
  # additive, never a replacement for this.
  def src
    url
  end

  # Whether this asset can have size variants at all: every allowed type
  # except GIF (global constraints: "GIFs get no variants") -- an animated
  # GIF is served as-is, its frames intact, rather than resized down into a
  # handful of static WebP stills.
  def variable_image?
    file.attached? && content_type != "image/gif"
  end

  # `[url_path, width]` pairs for every variant that's actually usable right
  # now (design spec §3.1, global constraints, Review Focus 3) -- skipping:
  #
  # - a GIF entirely (`#variable_image?`);
  # - any width at or above the original's own (`width.present? &&
  #   target_width >= width`) -- `resize_to_limit` already refuses to
  #   *upscale*, so a variant no bigger than the original would just be a
  #   redundant re-encode of it, not a smaller file a `srcset` should offer;
  # - a variant that hasn't *finished* processing (`Variant#processed?`) --
  #   preprocessing is a best-effort head start (the `has_one_attached`
  #   block's own comment), never something this waits on;
  # - a variant whose processing blew up (a corrupt upload, a `vips`
  #   error) -- caught and logged per variant, not left to bubble up and
  #   break the page around it.
  #
  # `width` (this asset's *own* dimensions column, from `file.analyze`) may
  # itself be nil -- analysis hasn't run, or failed (`MediaAssets::Create
  # #analyze_dimensions`'s own comment) -- in which case the "never upscale"
  # check is simply skipped for lack of anything to compare against; the
  # `processed?` check below still applies.
  def srcset
    return [] unless variable_image?

    VARIANT_WIDTHS.filter_map do |name, target_width|
      next if width.present? && target_width >= width

      variant = file.variant(name)
      # `Variant#processed?`/`VariantWithRecord#processed?` (`ActiveStorage
      # .track_variants`, on by default since `config.load_defaults 8.1`)
      # are both `private` -- on purpose, so nothing casually asks "is this
      # done yet" without also being tempted to reach for the public
      # `#processed`, which *runs* the transformation inline (a `vips` call
      # this method must never trigger; see the `has_one_attached` block's
      # own comment). `send` is the one way to ask the question without
      # triggering the answer.
      next unless variant.send(:processed?)

      [ Rails.application.routes.url_helpers.rails_representation_path(variant, only_path: true), target_width ]
    rescue StandardError => e
      Rails.logger.error("[media_assets] Media::Asset##{id} srcset variant #{name} failed: #{e.class}: #{e.message}")
      nil
    end
  end

  # The alt text a placement actually shows (global constraints: "override
  # .presence, then the asset's default in the locale, then the Mobility
  # fallback"): an explicit per-placement `override` always wins, then this
  # asset's own literal `alt` in `locale`, then the same cross-locale
  # fallback chain every other translated attribute reads through
  # (`Locales.read` -- plain Mobility readers no longer fall back on their
  # own, config/initializers/mobility.rb). Always a String, never nil: an
  # `<img alt="">` with nothing set anywhere is still valid HTML, and a
  # renderer should never have to guard against a nil alt attribute.
  def alt_text(override:, locale: I18n.locale)
    override.presence || Locales.read(self, :alt, locale: locale) || ""
  end

  # The same resolution order as `#alt_text`, but nil (not `""`) when
  # nothing is set anywhere -- an absent caption means "don't render a
  # <figcaption> at all", not "render an empty one".
  def caption_text(override:, locale: I18n.locale)
    override.presence || Locales.read(self, :caption, locale: locale)
  end

  private

  # `hero-photo.jpg` -> "hero-photo": the title an editor never has to type
  # before an upload is usable in a listing or a picker. `ActiveStorage
  # ::Filename#base` already strips the extension the same way the
  # migration's own backfill does in SQL. Only fills a *blank* title --
  # editable ever after, the same "presence decides, not overwrite" rule
  # `alt`/`caption`'s Mobility `presence` plugin use throughout this app.
  def set_default_title
    return if title.present? || !file.attached?

    self.title = file.filename.base
  end

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
    errors.add(:file, "doesn't match its stored content type") if stored_type_mismatch?
  end

  # Final fix wave (C, P5): an already-persisted blob (attached by signed id,
  # or as an `ActiveStorage::Blob`) is served with *its own* stored
  # `content_type`, which `#force_blob_content_type` deliberately never
  # rewrites (it's some other record's committed row). So the sniff passing
  # isn't enough there: a PNG stored as `text/html` would still be served as
  # HTML. Such a blob is refused instead. A new blob can't mismatch -- its
  # type is forced to the sniff before it's written.
  def stored_type_mismatch?
    blob = file.blob
    !blob.new_record? && sniffed_content_type.present? && blob.content_type != sniffed_content_type
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
  # `nil` (never a raise) when `#with_attachable_io` can't get at the bytes
  # at all -- an attachable this class doesn't know how to read yet (fix
  # round 1's I3: a signed blob id String, or an `ActiveStorage::Blob`
  # that's itself still unsaved). `ALLOWED_CONTENT_TYPES.include?(nil)` is
  # `false`, so that's just an ordinary "must be a PNG, JPEG, GIF, or WEBP
  # image" validation failure, exactly like a real file of some other type
  # would produce -- not a distinct error message, since from a caller's
  # point of view "I can't tell this is an allowed image type" and "this
  # definitely isn't one" both mean the same thing: don't accept it.
  #
  # Memoized: `image_type_and_size` and `#cache_metadata_from_file` both
  # want this same value for the same validated attachment, and neither
  # should re-read the underlying io to ask twice.
  def sniffed_content_type
    return @sniffed_content_type if defined?(@sniffed_content_type)

    @sniffed_content_type = with_attachable_io { |io| io && Marcel::MimeType.for(io) }
  end

  # Yields the raw io behind this record's `file` attachment to the block
  # (or `nil`, when there's no safe way to get one), from whichever of two
  # places it currently lives.
  #
  # `record.attachment_changes[name]` is Active Storage's own (`:nodoc:`,
  # but public) handle on a *pending* attachment -- one assigned via
  # `file.attach(...)` but not yet saved -- and `change.blob` is always the
  # underlying `ActiveStorage::Blob` that assignment actually resolved to,
  # for every shape `.attach` accepts (`Attached::Changes::CreateOne
  # #find_or_build_blob`): a `Hash`/`ActionDispatch::Http::UploadedFile`
  # each get a brand-new, unfurled-but-not-yet-uploaded `Blob.new`; a
  # signed id String or an already-persisted `ActiveStorage::Blob` passed
  # directly instead resolve to an *existing*, already-uploaded blob (found
  # by `Blob.find_signed!`, or the object itself). `blob.new_record?` is
  # what tells those two apart, and it's the one check this needs, not a
  # `case` on the attachable's own class: an existing blob already has real
  # bytes sitting on the storage service, so `blob.open` (the ordinary,
  # already-uploaded path below) reads it back exactly the way a persisted
  # `Media::Asset`, reloaded and re-validated, would.
  #
  # Only a genuinely *new* blob needs the workaround: it has nothing on the
  # storage service yet (Active Storage only uploads from an `after_commit`
  # hook that fires strictly after every `validate`), so `blob.open` would
  # raise `ActiveStorage::FileNotFoundError` there. For that case alone,
  # this reads `change.attachable` itself -- the literal `io:`/`filename:`/
  # `content_type:` Hash, or `ActionDispatch::Http::UploadedFile`, this
  # attachment was actually given -- the same object `unfurl` already read
  # once, for the blob's own checksum/byte_size, and rewound back to
  # position 0 (`ActiveStorage::Blob#compute_checksum_in_chunks`'s own
  # final `io.rewind`), so reading it again here for a second, independent
  # sniff is exactly as safe as Active Storage's own eventual upload
  # reading it a third time once this record is actually saved.
  #
  # Any *other* attachable shape for a still-new blob (fix round 1's I3: a
  # bare `File`/`Pathname` passed directly, say -- `.attach` accepts both,
  # this class just has no reader taught for either yet) has no safe way to
  # read bytes from at all -- yielding `nil` here, not calling an arbitrary
  # `.open`/`[:io]` on whatever it turns out to be, is what keeps that "I
  # don't recognize this" case a validation failure (`#sniffed_content_
  # type`'s own comment) instead of a `NoMethodError` 500.
  def with_attachable_io
    change = attachment_changes["file"]
    return yield(nil) if change.nil? && !file.attached?

    blob = change&.blob || file.blob
    return blob.open { |tempfile| yield(tempfile) } unless blob.new_record?

    attachable = change.attachable
    case attachable
    when Hash then yield(attachable[:io])
    when ActionDispatch::Http::UploadedFile, Rack::Test::UploadedFile then yield(attachable.open)
    else yield(nil)
    end
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
    force_blob_content_type

    # Merged onto whatever's already there, not overwritten outright: a
    # second save of an already-analyzed asset (nothing about this model
    # re-attaches a file after the fact today, but nothing rules it out
    # later either) must not blank out real `width`/`height` this callback
    # itself has no way to recompute yet.
    metadata = file.blob.metadata || {}
    self.width = metadata["width"] if metadata.key?("width")
    self.height = metadata["height"] if metadata.key?("height")
  end

  # Fix round 1's I4: `file.blob.content_type` -- the column that actually
  # decides what Content-Type this asset gets *served* with
  # (`ActiveStorage::Blob#service_metadata`) -- otherwise still comes from
  # Rails' own `unfurl`, which (by default, `identify: true`) re-derives it
  # from the upload's declared Content-Type *and* filename, not only its
  # bytes (`ActiveStorage::Blob#extract_content_type`'s own `Marcel
  # ::MimeType.for(io, name:, declared_type:)` call -- the exact
  # attacker-trusting shape `#sniffed_content_type`'s own comment already
  # refuses to use for *this* model's validation). Two independent sniffs
  # of the same bytes, by two different rules, can disagree -- so this
  # forces the one that's actually served to equal the one this class
  # already validated against, rather than trust they happened to agree.
  #
  # Only for a blob this save is *creating* (`new_record?`): an already-
  # persisted, already-uploaded blob reached via a signed id or a directly-
  # assigned `ActiveStorage::Blob` (`#with_attachable_io`'s own comment) is
  # some other record's own already-committed row, not this save's to
  # silently rewrite -- and nothing here needs to, since `unfurl` never
  # touches an existing blob's `content_type` in the first place. Guarded
  # on `sniffed_content_type` being present too: a still-new blob this
  # class genuinely can't sniff (I3 above) leaves the blob's own `identify`d
  # guess alone rather than overwriting it with `nil`, though that guess is
  # moot either way -- an unsniffable attachment is already invalid
  # (`#image_type_and_size`), so this record is never getting saved with it.
  def force_blob_content_type
    return unless sniffed_content_type && file.blob.new_record?

    file.blob.content_type = sniffed_content_type
  end
end
