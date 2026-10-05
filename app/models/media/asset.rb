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

  # Fix round 1 (I2/I3): every list that calls `#srcset` on more than one
  # asset -- a library listing, a picker -- must load through this scope.
  # `#srcset` answers "is this variant processed" by reading `file.blob
  # .variant_records` (`#processed_variant_digests`'s own comment); without
  # this preload that's one query per asset, and `.variant_records` itself
  # nested three associations deep (`file_attachment` -> `blob` ->
  # `variant_records`) isn't something `includes` infers on its own from a
  # bare `Media::Asset.all`. This is deliberately narrower than the
  # `with_attached_file` scope `has_one_attached` already generates (which
  # also preloads each variant's own attached image, `image_attachment:
  # :blob` -- a second N+1 `#srcset` has no use for, since all it ever reads
  # off a `variant_records` row is `variation_digest`).
  # The `includes` shape itself, pulled out to a constant (media library
  # Task 5) so a caller that can't just call `.with_variants` on a
  # `Media::Asset` relation -- because it's preloading *through* another
  # model's association instead, e.g. `PublicPageRendering`'s `belongs_to
  # :hero_media_asset`/`has_many :content_blocks -> belongs_to :media_asset`
  # via `ActiveRecord::Associations::Preloader` -- can still ask for exactly
  # this same shape rather than hand-copying it.
  VARIANT_INCLUDES = { file_attachment: { blob: :variant_records } }.freeze

  scope :with_variants, -> { includes(VARIANT_INCLUDES) }

  has_one_attached :file do |attachable|
    # Every responsive width the public site can ever ask for, preprocessed
    # right after upload (a truthy `preprocessed:` enqueues one `ActiveStorage
    # ::TransformJob` per variant, from `ActiveStorage::Attachment`'s own
    # `after_create_commit :transform_variants_later`, as soon as this
    # attachment's blob finishes uploading) so a variant is normally already
    # sitting on the storage service by the time a page first requests it --
    # but never something a page *waits* on: `#srcset` below only ever lists
    # a variant that's already finished (`#processed_variant_digests`), so a
    # slow, still-queued or failed job just means fewer `srcset` entries for
    # this request, never a request that blocks on -- or 500s over -- one.
    #
    # `preprocessed:` takes a `Proc` (`ActiveStorage::NamedVariant
    # #preprocessed?`: `Proc` gets `.call(record)`, `Symbol` gets `record
    # .send(...)`) called with the owning `Media::Asset` itself -- fix round
    # 1's I1 (a plain `true` here doesn't condition on content type at all,
    # so a GIF's `w480`..`w2400` were being enqueued and processed every
    # upload, wastefully generating four resized-still WebPs of an
    # animation no page has ever shown -- `#variable_image?` already exists
    # for exactly this check, but nothing read it before enqueuing). Called
    # from `transform_variants_later`'s own `after_create_commit`, strictly
    # after this record's `before_save :cache_metadata_from_file` has run
    # and that whole save has committed, so `record.content_type` -- what
    # `#variable_image?` actually reads -- is always the real, sniffed
    # value by the time this proc runs, never the pre-save `nil`.
    VARIANT_WIDTHS.each do |name, target_width|
      attachable.variant name, resize_to_limit: [ target_width, nil ], format: :webp,
        preprocessed: ->(asset) { asset.variable_image? }
    end
  end

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

  # Every committed change to a library image moves the public content
  # version (`PublicSite`, technical cleanup spec §4.8): an upload, its
  # title, alt or caption, the trash and a purge -- and a `touch`, which is
  # what replacing the attached file does. Used or not: a rendered page bakes
  # in the image's URL, alt, caption and dimensions, and whether a *live*
  # page shows this image is a lookup across heroes, image blocks and
  # rich-text bodies, which costs more than the bump it would save.
  after_commit { PublicSite.bump_version! }

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

  # CS Studio's thumbnail for this image (design spec §6: the Media grid,
  # the picker, a hero/image-block field): the `w480` variant once it's
  # processed, else the original. `#srcset` only ever lists a finished
  # variant, so "processed" is just "present in that list" -- and it
  # skips GIFs and anything narrower than 480px, which fall back to the
  # original. Load through `with_variants` when rendering several.
  def thumbnail_url
    w480_url, = srcset.find { |_url, width| width == VARIANT_WIDTHS[:w480] }
    w480_url || src
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
  # - a variant that hasn't *finished* processing (`#processed_variant_
  #   digests`) -- preprocessing is a best-effort head start (the
  #   `has_one_attached` block's own comment), never something this waits
  #   on;
  # - a variant whose processing blew up (a corrupt upload, a `vips`
  #   error) -- caught and logged per variant, not left to bubble up and
  #   break the page around it.
  #
  # `width` (this asset's *own* dimensions column, from `file.analyze`) may
  # itself be nil -- analysis hasn't run, or failed (`Media::Upload
  # #analyze_dimensions`'s own comment) -- in which case the "never upscale"
  # check is simply skipped for lack of anything to compare against; the
  # processed check below still applies.
  def srcset
    return [] unless variable_image?

    digests = processed_variant_digests

    VARIANT_WIDTHS.filter_map do |name, target_width|
      next if width.present? && target_width >= width

      variant = file.variant(name)
      next unless digests.include?(variant.variation.digest)

      [ Rails.application.routes.url_helpers.rails_representation_path(variant, only_path: true), target_width ]
    rescue StandardError => e
      Rails.logger.error("[media_assets] Media::Asset##{id} srcset variant #{name} failed: #{e.class}: #{e.message}")
      nil
    end
  end

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

    loaded.group_by { |usage| [ usage.owner_type, usage.owner_id ] }.map do |_key, group|
      {
        owner: group.first.owner,
        roles: group.map(&:role).uniq,
        locales: group.filter_map(&:locale).uniq
      }
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

  # The `ActiveStorage::VariantRecord#variation_digest` for every variant of
  # this asset's blob that's already been processed -- fix round 1's I2/I3:
  # `Variant#processed?`/`VariantWithRecord#processed?` are both `private`
  # (deliberately: the public alternative, `#processed`, *runs* the
  # transformation inline the moment it isn't done yet, a `vips` call
  # `#srcset` must never trigger -- see the `has_one_attached` block's own
  # comment), so this reads the same thing those private methods themselves
  # read (`VariantWithRecord#record`'s own `blob.variant_records.find_by
  # (variation_digest: ...)`) through the public, documented `variant_
  # records` association instead.
  #
  # One query total for *all four* widths, not one per width and not one
  # per asset: `variant_records.loaded?` is true when a caller preloaded it
  # (`Media::Asset.with_variants`, which every multi-asset list must use),
  # in which case this reads the already-loaded rows in memory; otherwise
  # `pluck` issues the one query itself. Either way, comparing a `Set` of
  # digests against each variant's own `variation.digest` (`#srcset`) never
  # queries per variant.
  def processed_variant_digests
    variant_records = file.blob.variant_records
    digests = variant_records.loaded? ? variant_records.map(&:variation_digest) : variant_records.pluck(:variation_digest)
    digests.to_set
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
  # this callback: `Media::Upload#analyze_dimensions` calls
  # `analyze` (and writes these two columns) in a second pass, strictly
  # after this record's own save has actually committed and Active
  # Storage's own `after_commit` hook has uploaded the blob's bytes --
  # analysis needs the real file on the storage service, which isn't there
  # yet at `before_save` time (`#with_attachable_io`'s own comment). So
  # this callback leaves both nil on every ordinary save; that's fine,
  # neither is a NOT NULL column, and `Media::PictureComponent` (media
  # library Task 5, the one place every image render reads these) just
  # omits the `<img width height>` attributes it would otherwise set from
  # them -- `image_tag` drops a `nil` attribute rather than rendering it
  # empty.
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
