# One library image (media library design spec §3.1): what a page's hero
# (`Page#hero_media_asset`), an image block (`ContentBlock#media_asset`) and
# a rich-text `image` node's `asset_id` (`RichText::BuiltIns`) all reference
# -- since Task 4 there is one storage path for all three. Uploaded through
# `Media::Upload`; where it's used is indexed in `media_usages`
# (`Media::UsageIndex`), and the FKs into `media_assets` keep a used
# asset from being deleted. Cleanup of unused assets is manual only.
class Media::Asset < ApplicationRecord
  extend Mobility
  include Trashable

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

  # This asset's own translated defaults for alt text and caption -- jsonb,
  # same shape and backend as every other translated attribute in this app
  # (config/initializers/mobility.rb). A *placement* (a rich-text image
  # node, an image content block) can still override either of these per
  # use, which is exactly what `#alt_text`/`#caption_text` below resolve --
  # reading `alt`/`caption` directly only ever gets this asset's own literal
  # default in the ambient locale, never an override or a cross-locale
  # fallback.
  translates :alt, :caption

  # Which version of the original alt/caption each translation was saved
  # against (translation helpers spec §3.2).
  include Translations::Tracker
  tracks_translations

  belongs_to :created_by, class_name: "User", optional: true

  # Where this asset is actually used (design spec §3.2) -- entirely
  # derived, rebuilt wholesale by `Media::UsageIndex.refresh(owner)`
  # whenever an owner's own state might have changed, never written to
  # directly. `dependent:` is deliberately left unset: the database's own
  # FK (NO ACTION, see `MediaForeignKeysNoAction`) is what actually backs "can't delete an
  # asset that's in use" (global constraints, Review Focus 4) -- an
  # `:restrict_with_exception` here would only intercept an ordinary
  # `#destroy` with a *different* exception (`DeleteRestrictionError`)
  # before the query ever reaches Postgres, which would both duplicate the
  # database's own guarantee and hide the `ActiveRecord::InvalidForeignKey`
  # a bypassed or racing delete (`Trash::Purge`'s own service-level check
  # losing a race, or a raw `delete`) is still expected to surface.
  #
  # `foreign_key:` is explicit for the same reason `self.table_name` is:
  # Rails' default `has_many` foreign key is derived from this class's
  # *demodulized* name (`"Media::Asset".foreign_key` -> `"asset_id"`), not
  # the real `media_usages.media_asset_id` column.
  has_many :usages, class_name: "Media::Usage", foreign_key: :media_asset_id

  # The "Unused" filter (design spec §6): an asset with no `usages` row at
  # all. `where.missing`, not a `left_joins` + `where(usages: { id: nil })`
  # by hand -- same result, the query planner just gets to see the intent
  # directly.
  scope :unused, -> { where.missing(:usages) }

  # The `includes` shape every list that draws an asset's image loads it by.
  # The generation is a column of the row, so an address needs the file's
  # blob (its signed id and filename) and nothing more: no variant record is
  # read. A caller that preloads *through* another model's association
  # (`PublicPageRendering`'s hero and image blocks) asks for this same shape.
  FILE_INCLUDES = { file_attachment: :blob }.freeze

  scope :with_file, -> { includes(FILE_INCLUDES) }

  # No variant is declared here: the widths of an image are made by
  # `Media::RenditionJob`, recorded in `renditions`, and addressed through
  # the blob's representation proxy by the keys that generation holds.
  has_one_attached :file

  before_validation :set_default_title

  validate :file_is_attached
  validate :image_type_and_size, if: :file_changing?

  # Cache the *validated* content type/size onto their own columns right
  # before a valid record is written -- never in a `before_validation`,
  # which would let this stomp whatever `image_type_and_size` is about to
  # check against with a value nobody has verified yet. Reading these back
  # off the record (a listing, this upload's own JSON response) is then a
  # plain column read, not a re-open of the blob to re-sniff bytes that
  # were already sniffed once, at save time, for the validation this
  # callback is piggybacking on.
  #
  # Both this and `image_type_and_size` run only when a file is being
  # attached (`#file_changing?`, final fix wave I2): the file never changes
  # after upload, so re-checking it on an edit of the title or alt text
  # re-read it from the storage service -- a download of up to 10 MB per
  # autosave, and a failed save whenever the stored file was unreachable.
  before_save :cache_metadata_from_file, if: :file_changing?

  # A committed change to a library image (an upload, its title, alt or
  # caption, the trash, a purge, a `touch`) moves the public content version
  # only when a live page can show the image: a rendered page bakes in the
  # image's address, alt, caption and dimensions, and a page that does not use
  # it holds none of them. No race loses a bump: the usage rows are written in
  # the transaction of the save that makes a page use the image, and that save
  # moves the version itself when it publishes; a change committed here before
  # that row exists is read by the page's later render, and one committed
  # after finds the row. A question that fails answers yes: a needless bump
  # costs a cache, a missed one a stale page.
  after_commit { PublicSite.bump_version! if shown_publicly? }

  def shown_publicly?
    usages.shown_publicly.exists?
  rescue StandardError => e
    Rails.logger.error("[media_asset] shown_publicly? failed: #{e.class}")
    true
  end

  # The widths are made once the upload has committed, on the images queue
  # (`Media::RenditionJob`); until then the preview stands in for the image.
  after_create_commit { Media::RenditionJob.perform_later(self) }

  # The generation the public site is served from: the widths made with the
  # settings in force when they were made, as recorded on the row. Nothing
  # here reads the storage service, a variant record or the original, so a
  # list of fifty assets loaded `with_file` costs no query to address.
  def generation(name = "current")
    Media::Generation.from((renditions || {})[name])
  end

  def made? = generation.present? && generation.files.any?

  def made_with?(fingerprint)
    made? && generation.fingerprint == fingerprint
  end

  # The variation digests of every width a page may still name: the current
  # generation's and the previous one's, which a page cached before the switch
  # still lists. The public representation routes serve these and nothing else
  # of a library image (`ActiveStoragePublicFiles`).
  def served_digests
    %w[current previous].flat_map { |name| generation(name)&.files.to_a.map(&:digest) }.compact_blank
  end

  # `[address, width]` for every width made, ascending; empty without a
  # generation. A bare path: no query, no host. The original is never a
  # candidate: only a file this app made is addressed.
  def srcset
    return [] unless made? && file.attached?

    generation.files.map { |made| [ rendition_path(made), made.width ] }
  end

  # The address an `<img src>` takes: the middle of the widths made (the one
  # a browser without `srcset` support is least badly served by), else the
  # preview as a data URI while none is made, else nothing. Never the
  # original.
  def src
    made_files = srcset
    return made_files[(made_files.size - 1) / 2].first if made_files.any?

    preview_data_url
  end

  # The ~24px preview as a `data:` URI, strict base64, or nil without one.
  def preview_data_url
    return nil if preview.blank?

    "data:image/webp;base64,#{Base64.strict_encode64(preview)}"
  end

  # The smallest width made that covers `min_width`, else the largest made,
  # else the preview, else nil.
  def display_url(min_width:)
    made_files = srcset
    return preview_data_url if made_files.empty?

    (made_files.find { |_url, width| width >= min_width } || made_files.last).first
  end

  # True for the `data:` URI the preview is drawn as (never an address).
  def self.preview_url?(url) = url.to_s.start_with?("data:")

  # CS Studio's thumbnail (the Media grid, the picker, an image field).
  def thumbnail_url = display_url(min_width: 480)

  # The alt text a placement actually shows (global constraints: "override
  # .presence, then the asset's default in the locale, then the Mobility
  # fallback"). `override` comes in one of two shapes:
  #
  # - a String (or nil) -- a rich-text `image` node's own `alt` attr, which
  #   is single-valued (it lives inside one locale's document already): it
  #   wins when present, else this asset's default walks the fallback
  #   chain (`Locales.read` -- plain Mobility readers no longer fall back
  #   on their own, config/initializers/mobility.rb);
  # - a `{locale => value}` Hash -- a *translated* override column read
  #   whole (`block.read_attribute(:alt)`, `page.read_attribute(:hero_alt)`).
  #   Final fix wave (I1): the two are interleaved per locale -- the
  #   override in a locale, then this asset in that locale, then the next
  #   locale in `Locales.fallback_chain`. Resolving the override through the
  #   chain first (what `translated(block, :alt)` did) let an `en`-only
  #   block alt beat the asset's own `de` default on a `de` page: the
  #   override is only "the editor's choice" in the language it was
  #   written in.
  #
  # Always a String, never nil: an `<img alt="">` with nothing set anywhere
  # is still valid HTML, and a renderer should never have to guard against
  # a nil alt attribute.
  def alt_text(override:, locale: I18n.locale)
    resolve_translated(:alt, override, locale) || ""
  end

  # The same resolution order as `#alt_text`, but nil (not `""`) when
  # nothing is set anywhere -- an absent caption means "don't render a
  # <figcaption> at all", not "render an empty one".
  def caption_text(override:, locale: I18n.locale)
    resolve_translated(:caption, override, locale)
  end

  # Whether anything currently references this asset -- the same question
  # the database's own FK answers at delete time,
  # asked ahead of that (design spec §5.1: `Trash::Purge`'s own usage
  # check, the "Unused" filter's inverse).
  def used?
    usages.exists?
  end

  # Whether any *kept* Page/Post (a block's usage counts through the block's
  # own owner -- the second hop `Media::Usage.by_kept_owner` already does)
  # still references this asset (trash spec §4.1/§5.1). Moving an image to
  # the trash is refused while this is true; purging asks the plain `#used?`
  # instead, since a purge must also be refused for an asset a *trashed*
  # owner still points at -- restoring that owner would otherwise resurrect
  # a dangling reference.
  def used_by_kept_owner?
    usages.by_kept_owner.exists?
  end

  # Which of the three "Used on"/Delete states this asset is in (trash spec
  # §4.1, media library design spec §6): nothing references it at all, a
  # kept page or post still does, or every reference left is to something in
  # the trash. `#used?` stays the coarse any-usage-at-all question purging
  # (and the database's own FK) actually needs; this is the finer question
  # CS Studio's detail panel renders around.
  def usage_state
    return :unused unless used?

    used_by_kept_owner? ? :in_use : :trash_only
  end

  # One entry per distinct place this asset is used -- grouped by owner,
  # not one entry per `media_usages` row: a post whose `en` and `de` bodies
  # both embed this image is one link in "Used on" (design spec §6), not
  # two, even though it's two `rich_text` rows internally. `roles`/
  # `locales` fold each group's rows back together for a caller that wants
  # to say *how* it's used there (e.g. "rich text, in en, de") without
  # re-querying.
  def usages_summary
    loaded = usages.includes(:owner).to_a
    self.class.preload_usage_places(loaded.map(&:owner))

    entries = loaded.group_by { |usage| [ usage.owner_type, usage.owner_id ] }.map do |_key, group|
      {
        owner: group.first.owner,
        roles: group.map(&:role).uniq,
        locales: group.filter_map(&:locale).uniq
      }
    end
    # A record counts once. The published copy's row (`published`) says "the
    # site still shows this image" and is named only when nothing in the rows
    # shows it any more: it is left out of a group that has another role, and
    # a group of it alone is left out when the same page or post (itself or
    # through one of its blocks) has another group.
    entries.each { |entry| entry[:roles] -= [ "published" ] if entry[:roles].size > 1 }
    covered = entries.reject { |entry| entry[:roles] == [ "published" ] }.filter_map { |entry| usage_place_of(entry[:owner]) }
    entries.reject { |entry| entry[:roles] == [ "published" ] && covered.include?(usage_place_of(entry[:owner])) }
  end

  # `{ asset id => [place, ...] }` for these assets: the pages and posts that
  # use each by a kept owner, every place once however many ways it uses the
  # image (hero, blocks, bodies, the published copy). The one place the MCP
  # tools' `usage_count`s come from, so `list_media` and `get_media` agree.
  def self.usage_places_for(asset_ids)
    usages = Media::Usage.where(media_asset_id: asset_ids).by_kept_owner.includes(:owner).to_a
    preload_usage_places(usages.map(&:owner))
    usages.group_by(&:media_asset_id).transform_values do |rows|
      rows.filter_map { |usage| usage.owner.is_a?(ContentBlock) ? usage.owner.owner : usage.owner }.uniq
    end
  end

  # How many places `#in_use_message` names before summing up the rest as
  # "and N more".
  IN_USE_NAMED_PLACES = 3

  # "This image is used on the page “About”, the post “Hello” and 2 more" --
  # why an image can't go (moved here from the retired `Media::Destroy`,
  # trash spec §4.1, so `Trash::Move` and `Trash::Purge` share one wording). A
  # block's usage is named by the page or post it sits on, and a place is
  # named once however many ways it uses the image (a hero and a block on
  # the same page, a body image in two locales). A place `actor` can't read
  # isn't disclosed ("not found, not forbidden"): it's "a page you can't
  # open" instead of its title.
  #
  # `kept_only:` limits it to usages by kept owners (`Media::Usage
  # .by_kept_owner`) -- what refuses a move to the trash, where a usage by a
  # page already in the trash doesn't count. `actor:` is whoever the refusal
  # is for (a service's own `actor`, which may differ from `Current.actor`).
  def in_use_message(kept_only: false, actor: Current.actor)
    scope = kept_only ? usages.by_kept_owner : usages
    loaded = scope.includes(:owner).order(:id).to_a
    # Fix round 1 (review of `0695e7a`): batches the `ContentBlock#owner`
    # second hop for every block-owned row in one shot, one query per
    # owner type (Page, Post) -- see `.preload_usage_places`'s own comment
    # for why this can't just share `#usages_summary`'s own query (this
    # needs the strict `.order(:id)` above, which that method doesn't
    # promise).
    self.class.preload_usage_places(loaded.map(&:owner))
    places = loaded.map { |usage| usage_place_of(usage.owner) }.compact.uniq
    # Only rows whose owner is already gone (a stale index): still refused.
    # No verb, since both moving to the trash and purging answer with this.
    return "This image is still in use" if places.empty?

    named = places.first(IN_USE_NAMED_PLACES).map { |place| describe_usage_place(place, actor) }
    named << "#{places.size - IN_USE_NAMED_PLACES} more" if places.size > IN_USE_NAMED_PLACES

    "This image is used on #{named.to_sentence(two_words_connector: " and ", last_word_connector: " and ")}"
  end

  # Batches the second hop every caller of a `media_usages` row's owner
  # needs for a `block_image`/`rich_text` usage: which page or post the
  # owning `ContentBlock` actually sits on (`ContentBlock#owner`, itself
  # polymorphic). Fix round 1 (review of `0695e7a`): `#usages_summary`'s
  # own `owner: group.first.owner` and `#in_use_message`'s
  # own `usage_place_of` both used to call that bare `.owner` once per
  # `ContentBlock`-owned usage -- fine for the "and 2 more" case `#in_use_
  # message` truncates to, but a real N+1 once an asset (or a delete
  # attempt's own full count) is used on a page full of image blocks
  # (Admin::MediaLibrary::PanelComponent's own "Used on" list, unlike
  # `#in_use_message`, never truncates at all).
  #
  # A public class method, not a private instance one: `#in_use_message`
  # runs its own separate `@asset.usages.includes(:owner)
  # .order(:id)` query (it needs a strict id order `#usages_summary`
  # doesn't promise, so the two can't simply share one query) and calls
  # this directly on its own loaded batch, rather than duplicating the
  # preload logic or bending its own ordering to reuse `#usages_summary`.
  #
  # `ActiveRecord::Associations::Preloader`, not a bare `.owner` call per
  # block (this app's own established pattern for exactly this shape --
  # see `Admin::PagesController#show`/`PublicPageRendering
  # #preload_page_images`): `owner` is itself polymorphic (Page or Post),
  # and the preloader groups each block by its own already-known
  # `owner_type` before querying, so this is one query per owner *type*
  # actually present among `owners` (at most two: Page, Post), never one
  # per block -- the ruling's own "one query per owner type" shape.
  def self.preload_usage_places(owners)
    blocks = owners.select { |owner| owner.is_a?(ContentBlock) }.uniq
    return if blocks.empty?

    ActiveRecord::Associations::Preloader.new(records: blocks, associations: :owner).call
  end

  private

  # The proxy representation path of one made width: the blob's signed id and
  # the signed variation key the generation recorded.
  def rendition_path(made)
    Rails.application.routes.url_helpers.rails_blob_representation_proxy_path(
      signed_blob_id: file.blob.signed_id, variation_key: made.key, filename: file.filename, only_path: true
    )
  end

  def usage_place_of(owner) = owner.is_a?(ContentBlock) ? owner&.owner : owner

  def describe_usage_place(place, actor)
    kind = place.is_a?(Post) ? "post" : "page"
    return "a #{kind} you can't open" unless AccessControl.allowed?(actor, "#{kind}s.read", place)

    "the #{kind} “#{Audit::Snapshot.label_for(place)}”"
  end

  # `#alt_text`/`#caption_text`'s shared walk (see `#alt_text` for the two
  # shapes `override` takes). Each step reads a literal per-locale value,
  # the same way `Locales.read` does.
  def resolve_translated(attribute, override, locale)
    return override.presence || Locales.read(self, attribute, locale: locale) unless override.is_a?(Hash)

    overrides = override.transform_keys(&:to_s)
    Locales.fallback_chain(locale).each do |code|
      value = overrides[code].presence || Mobility.with_locale(code) { public_send(attribute) }.presence
      return value if value
    end
    nil
  end

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

  # A pending attachment (`file.attach(...)` not yet saved) -- Active
  # Storage's own handle on it, `attachment_changes` (see
  # `#with_attachable_io`). Present only on the save that attaches a file.
  def file_changing?
    attachment_changes["file"].present? && file.attached?
  end

  # The one rule design spec §4.2 states (global constraints: "png/jpeg/gif/
  # webp only, max 10 MB") -- checked against the blob's *actual* bytes, not
  # whatever the upload's own Content-Type header or filename claimed (see
  # `#sniffed_content_type`'s own comment: that's exactly the pair an
  # attacker controls, and exactly the pair Marcel's own sniffing falls back
  # to *trusting* when asked to guess from a name/declared type it hasn't
  # ruled out with real magic bytes).
  def image_type_and_size
    max = ImageSettings.current.max_bytes
    errors.add(:file, :too_large, size: "#{max / 1.megabyte} MB") if file.blob.byte_size > max
    errors.add(:file, "must be a PNG, JPEG, GIF, or WEBP image") unless ALLOWED_CONTENT_TYPES.include?(sniffed_content_type)
    errors.add(:file, "doesn't match its stored content type") if stored_type_mismatch?
    # Decoded only once everything above passed: a file the byte sniff or the
    # size refuses is never handed to libvips.
    decode_file if errors.empty?
  end

  # The one decode of the upload (`Media::Decoding`), kept for
  # `#cache_metadata_from_file`, which writes its size, preview and alpha
  # flag in the same save.
  def decode_file
    @decoded = with_attachable_io { |io| io && Media::Decoding.read(io, content_type: sniffed_content_type) }
    errors.add(:file, :unreadable) if @decoded.nil?
  rescue Media::Decoding::TooManyPixels
    errors.add(:file, :too_many_pixels)
  rescue Media::Decoding::Unreadable
    errors.add(:file, :unreadable)
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

  # The size, preview and alpha flag are the validation's one decode
  # (`#decode_file`); the file's bytes are not read again.
  def cache_metadata_from_file
    self.byte_size = file.blob.byte_size
    self.content_type = sniffed_content_type
    force_blob_content_type

    self.width = @decoded.width
    self.height = @decoded.height
    self.preview = @decoded.preview
    self.has_alpha = @decoded.alpha
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
