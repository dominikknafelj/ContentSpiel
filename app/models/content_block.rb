# One row per block, in `position` order, on whatever owns it -- only `Page`
# today, but the owner is polymorphic (open-types spec §4.1) so a future
# owner (a snippet, say) can hold blocks the same way. All block types share
# this table and are told apart by `block_type`, a plain string checked
# against the `BlockTypes` registry rather than a closed enum -- the same
# registry-backed shape `Post#content_type` uses for its own types (open-types
# spec §3). Which columns matter depends on the type: `body` (per-locale JSON
# documents, see `HasRichTextBody`) for rich_text,
# `image` + `caption` for image, `settings`/`translated_settings` for
# post_list.
class ContentBlock < ApplicationRecord
  extend Mobility

  # jsonb columns holding one caption/alt text per locale; reading or writing
  # them goes through the current Mobility.locale. (`backend: :jsonb` is the
  # app-wide default set in config/initializers/mobility.rb, so it isn't
  # repeated here -- same as Post's and Page's translated plain-text
  # attributes.) `alt` only makes sense for `image` blocks, but it's declared
  # unconditionally since Mobility attributes are defined at class-load time.
  translates :caption, :alt

  # `body_document(locale:)`/`assign_body` over the jsonb `body` column
  # (design spec §3.1) -- only `rich_text` blocks (`t.uses :body`) ever
  # write one, but like `caption`/`alt` it's declared unconditionally.
  include HasRichTextBody

  belongs_to :owner, polymorphic: true

  has_one_attached :image

  validates :block_type, presence: true

  # `position` is NOT NULL with a database default, which covers a block
  # created in code but not one whose position input the admin cleared: that
  # submits an empty string, which casts to nil and reaches Postgres as a raw
  # not-null violation rendered into the form. Validated so it comes back as a
  # form error instead.
  validates :position, presence: true

  # Every block card in CS Studio's editor (`app/components/admin/
  # block_card_component.rb`) carries the same `settings` inputs, whatever
  # the block's type, so a rich_text block would otherwise be saved holding
  # `{"content_type" => "", "tag" => "", "limit" => ""}` --
  # written straight onto the `settings` column by Rails' own nested
  # attributes, bypassing `assign_settings` entirely. Re-deriving `settings`
  # from the type's own field schema before every validation is what
  # actually replaces the old blanket `discard_blank_settings`: a field that
  # doesn't belong to this `block_type` (or a blank value for one that does)
  # is dropped by `ContentModel::FieldSet#untranslated_hash`, the same way it
  # would be through `assign_settings` -- this just makes that happen
  # regardless of which path wrote `settings`.
  before_validation :normalize_settings

  # Checked at validation time, not by a database constraint (open-types spec
  # §4.2): a `block_type` naming a type that isn't (or is no longer)
  # registered -- a typo, a removed plugin -- comes back as an ordinary
  # validation error rather than the enum's old `ArgumentError`, which would
  # otherwise crash the request instead of coming back through the normal
  # error path (a service's `Result#failure`).
  validate :block_type_is_registered

  # Delegates to the type's own `ContentModel::FieldSet` (built from its field
  # schema) rather than a hand-written check like the old
  # `post_list_settings_reference_a_real_content_type` -- every type's
  # `settings` are validated the same way, not just post_list's.
  validate :settings_are_valid

  # A post_list block's own criteria decide which posts have a canonical URL
  # under it (spec §5.3): adding, editing or removing one can hand a post its
  # first URL, move it to a different listing, or take it away entirely. Every
  # one of those has to re-run `PublicSite::Paths.canonical_page` for the
  # affected posts, not just the ones this block already lists -- edited to a
  # narrower `content_type`/`tag` still has to release the posts it no longer
  # matches. `sync_posts` re-derives each post's canonical page from scratch,
  # so it's called for both the block's current content type (after_save) and,
  # when a save or destroy changes which type that was, the previous one too.
  after_save :sync_listed_post_paths
  after_destroy :sync_listed_post_paths

  # Blocks whose type has the `lists_posts` capability (open-types spec §6) --
  # what `PublicSite::Paths`, the resolver's permalink fallback and
  # `PublicPageRendering#assign_record` all mean by "the listing blocks" now
  # that `post_list` is a registered type rather than a hardcoded enum value.
  scope :listing, -> { where(block_type: BlockTypes.with_capability(:lists_posts).map(&:name)) }

  # `ActiveModel::Validations` aliases this to `#send` by default, which
  # chokes on the dotted paths `settings_are_valid` below adds errors under
  # (`settings.content_type` is not a method) -- generating an error's full
  # message reads the attribute's current value through this. Same fix as
  # `ContentModel::FieldSet::Base`'s own override, for the same reason.
  def read_attribute_for_validation(key)
    respond_to?(key) ? public_send(key) : nil
  end

  # This block's registered type, or nil for a stored `block_type` that isn't
  # (or is no longer) registered -- e.g. a removed plugin's type. `find`, not
  # `fetch`: an unknown stored type must never raise here, since this is read
  # from render and path-sync boundaries that a stale record must not be able
  # to 500 (global constraints).
  def definition = BlockTypes.find(block_type)

  # The type's `ContentModel::FieldSet` instance over this block's
  # `settings`/`translated_settings`, or nil when `block_type` isn't
  # registered (there is no schema to build one from).
  def settings_object(locale: I18n.locale, fallback: false)
    definition&.field_set&.new(settings, translated_settings, locale:, fallback:)
  end

  # Casts and validates `hash` against the type's schema, then writes the
  # result back onto `settings`/`translated_settings`. Does nothing for an
  # unregistered type -- there is no schema to assign against, and
  # `block_type_is_registered` is what reports that instead.
  def assign_settings(hash, locale:)
    object = settings_object(locale:) or return

    object.assign(hash)
    self.settings = object.untranslated_hash
    self.translated_settings = object.all_translations.merge(locale.to_s => object.translated_hash).compact_blank
  end

  # The published posts this block is responsible for: its listing renders
  # them (newest first, trimmed to `settings.limit`) and its page serves a
  # permalink for each of them. Delegates to `BlockTypes::PostList` -- the
  # only type with the `lists_posts` capability today, so there is nothing
  # yet to dispatch between; a second listing type would move this onto the
  # definition itself instead (`t.lists_posts_with ...`).
  def listed_posts(include_unpublished: false)
    return Post.none unless definition&.capability?(:lists_posts)

    BlockTypes::PostList.listed_posts(settings_object, include_unpublished: include_unpublished)
  end

  # Whether this block's listing would include `post`, ignoring publication --
  # see `BlockTypes::PostList.lists?` for the criteria themselves.
  # `PublicSite::Paths.canonical_page` (spec §5.3) needs this per-post rather
  # than per-scope test to collect every candidate listing for a post -- it
  # then ranks them by the listing page's publication, the block's
  # specificity and tree order itself; the *post's* own publication is the
  # resolver's to gate (spec §6.3).
  def lists?(post)
    definition&.capability?(:lists_posts) ? BlockTypes::PostList.lists?(settings_object, post) : false
  end

  private

  # `object.assign(settings)` (not just building `settings_object` and
  # reading `untranslated_hash` off it) is what makes this actually replace
  # `discard_blank_settings`: `settings_object` alone reads the raw hash as
  # *already* split into untranslated/translated by column, but the raw
  # `settings` this runs against is whatever Rails' nested attributes wrote
  # straight onto the column (see the class comment above `before_validation
  # :normalize_settings`) -- untranslated *and* translated keys mixed
  # together, since that write path knows nothing about the type's schema.
  # `FieldSet#assign` is what actually sorts a key by `field.translated?`;
  # skipping it (the previous version of this method) silently dropped every
  # translated key the raw form ever wrote, because `untranslated_hash`
  # only ever reads `@values`, never `@translations`. It lands in the site's
  # default locale specifically -- the raw `settings=` writer Rails' own
  # `accepts_nested_attributes_for` generates carries no locale of its own
  # (unlike `ContentBlocks::Save`'s own per-locale `assign_settings` calls),
  # so that's the only locale this path can write to.
  def normalize_settings
    # `locale: Locales.default` explicitly, not `settings_object`'s own
    # ambient-`I18n.locale` default: `object.assign` and `#translated_hash`
    # below both key off this same `@locale`, so building against a locale
    # that might not be `Locales.default` would both assign and read back
    # under the wrong key -- and then `all_translations.merge(Locales.default
    # => ...)` would stamp the *right* key with the *wrong* locale's value
    # while leaving a stray, never-cleaned entry under the ambient one.
    object = settings_object(locale: Locales.default) or return

    object.assign(settings)
    self.settings = object.untranslated_hash
    self.translated_settings = object.all_translations.merge(Locales.default => object.translated_hash).compact_blank
  end

  def block_type_is_registered
    errors.add(:block_type, "isn't a registered block type") if block_type.present? && BlockTypes.find(block_type).nil?
  end

  # `locale: Locales.default`, not `settings_object`'s own ambient-`I18n.locale`
  # default: a required translated setting is only ever *written* at
  # `Locales.default` (`normalize_settings`'s comment explains why), so
  # checking `required` against whatever `I18n.locale` a request happens to
  # leave ambient -- unrelated to the site's own default -- would reject a
  # block that saved correctly the moment those two locales disagree.
  def settings_are_valid
    object = settings_object(locale: Locales.default) or return
    return if object.valid?

    object.errors.each { |error| errors.add("settings.#{error.attribute}", error.type, message: error.message) }
  end

  # Every content type a post_list save or destroy could have handed a
  # canonical page to, or taken one away from: the block's content type as it
  # is now (skipped if this isn't -- or, on a save that changed `block_type`
  # away from a listing type, no longer is -- one), and, only on a save, the
  # content type it matched *before* this save (skipped when that doesn't
  # apply either). `_before_last_save` accessors read back the value from
  # before the save that just ran regardless of whether that particular
  # attribute changed in it, which is exactly "before this edit" whether the
  # edit touched `settings`, `block_type`, both, or neither -- and after a
  # destroy they read back the value from the *previous* save instead, which
  # for an otherwise-untouched record is simply its current value, so
  # `definition&.capability?(:lists_posts)` alone (still readable on a
  # destroyed record; only mutation is frozen) already covers that case
  # without a second lookup.
  #
  # `nil` here means "every content type", the same reading `listed_posts`
  # and `settings_are_valid` give a blank `content_type` field -- `presence`
  # is what keeps that blank from reaching `sync_posts` as `""`.
  def sync_listed_post_paths
    old_definition = BlockTypes.find(block_type_before_last_save)
    return unless definition&.capability?(:lists_posts) || old_definition&.capability?(:lists_posts)

    content_types_to_resync(old_definition).each { |content_type| PublicSite::Paths.sync_posts(content_type) }
  end

  def content_types_to_resync(old_definition)
    types = []
    types << settings_object&.content_type if definition&.capability?(:lists_posts)
    types << settings_before_last_save["content_type"].presence if old_definition&.capability?(:lists_posts)
    types.uniq
  end
end
