# One row per block, in `position` order, on whatever owns it -- only `Page`
# today, but the owner is polymorphic (open-types spec §4.1) so a future
# owner (a snippet, say) can hold blocks the same way. All block types share
# this table and are told apart by `block_type`, a plain string checked
# against the `BlockTypes` registry rather than a closed enum -- the same
# registry-backed shape `Post#content_type` uses for its own types (open-types
# spec §3). Which columns matter depends on the type: `body` (per-locale JSON
# documents, see `HasRichTextBody`) for rich_text,
# `media_asset` + `caption`/`alt` for image, `settings`/`translated_settings` for
# post_list, `settings` + `caption` for code.
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

  # Which version of the original each translation was saved against
  # (translation helpers spec §3.2), plus the block type's own
  # `translated: true` settings. Rolls up into the owner's state.
  include Translations::Tracker
  tracks_translations schema: :settings_object

  belongs_to :owner, polymorphic: true

  # An `image` block's image (design spec §3.3): a reference to a library
  # `Media::Asset` -- Task 4's data migration moved every former
  # `has_one_attached :image` onto this column, re-using the same blobs.
  # The block keeps its own per-use `alt`/`caption` overrides (translated,
  # above). `optional: true` here too: only an `image` block ever sets it,
  # and even that block type can be created before an image is chosen (the
  # block picker adds an empty card first).
  belongs_to :media_asset, class_name: "Media::Asset", optional: true

  # A block in a section (sections spec §3.1) names the section and its
  # 1-based column; both are nil for a top-level block. The block still
  # belongs to the page (`owner`): a section arranges, it owns nothing, which
  # is why every per-block rule -- permissions, autosave, translation
  # tracking, media usages -- reads the same for a block in a column.
  # No `dependent:` on `section_blocks`: a section is emptied or lifted by
  # `ContentBlocks::Destroy`, and the foreign key refuses anything else.
  belongs_to :section, class_name: "ContentBlock", optional: true, inverse_of: :section_blocks
  has_many :section_blocks, -> { order(:section_column, :position, :id) }, class_name: "ContentBlock",
    foreign_key: :section_id, inverse_of: :section

  # Only when the placement itself is new or changed (decision D15): a block
  # inside a section whose type is no longer registered fails every one of
  # these, and must still be editable until someone moves it out.
  validate :section_rules, if: -> { new_record? || section_id_changed? || section_column_changed? || block_type_changed? }

  # The blocks a page shows in its own list; `position` is counted among them.
  scope :top_level, -> { where(section_id: nil) }
  # The blocks of one container: a section's column, or (nil, nil) the top level.
  scope :in_column, ->(section, column) { where(section_id: section, section_column: column) }

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
  # first URL, move it to a different listing, or take it away entirely. The
  # block says that its PAGE was touched (`sync_listed_post_paths`) and
  # `PublicSite::Paths.refresh` looks at the posts that page gave an address
  # to until now and the ones its list blocks can list from now on; what the
  # block's settings were before the save is not asked.
  #
  # On a published or scheduled page that has a copy this finds nothing to
  # move: the page lists what its COPY lists (`PublicSite::Paths
  # .canonical_pages`), so the block's change gives and takes addresses when
  # the page's changes are published (the copy's own refresh). It still
  # runs, for a draft page and one written around the services, whose rows
  # are what is listed.
  after_save :sync_listed_post_paths
  after_destroy :sync_listed_post_paths

  # A block of a live page is published output, so every committed change to
  # one moves the public content version (`PublicSite`, technical cleanup
  # spec §4.8); a draft's blocks move nothing. The services also `touch` the
  # owner, whose own `after_commit` asks the same question -- this is for a
  # block written without them (a console save, a page destroyed with its
  # blocks).
  after_commit :bump_public_version_when_owner_live

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

  # How a typed setting's error names its field: `settings.limit` -> "Limit"
  # (the label its input carries, `Admin::Ui::FieldComponent#label_text`), so the
  # message reads "Limit must be greater than or equal to 1" in the card's
  # error slot, the flash and MCP alike. Rails would otherwise print the
  # dotted path as "Settings limit ...". Everything else -- the block's own
  # columns -- goes to Rails' default.
  def self.human_attribute_name(attribute, options = {})
    name = attribute.to_s
    return super unless name.start_with?("settings.") && name.size > "settings.".size

    name.delete_prefix("settings.").humanize
  end

  # This block's registered type, or nil for a stored `block_type` that isn't
  # (or is no longer) registered -- e.g. a removed plugin's type. `find`, not
  # `fetch`: an unknown stored type must never raise here, since this is read
  # from render and path-sync boundaries that a stale record must not be able
  # to 500 (global constraints).
  def definition = BlockTypes.find(block_type)

  # Whether this block holds other blocks: asked of the type's capability,
  # never of its name. False for an unregistered type.
  def container? = definition&.capability?(:container) || false

  # How many columns this block's layout has; 0 for a block that holds none
  # (and for a section whose type is gone, so its blocks all read as strays).
  def column_count = container? ? definition.columns.call(settings) : 0

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

  # The tag a list block's filter names, as an id; nil with no filter, and
  # nil when no tag has that name. A block rebuilt from a published copy
  # answers the id the copy recorded (`Publishing::Snapshot`), so a public
  # list keeps its posts when the tag is renamed. A row asks by name, now,
  # and never remembers the answer: its settings can change under it.
  attr_writer :listed_tag_id

  def listed_tag_id
    return @listed_tag_id if instance_variable_defined?(:@listed_tag_id)

    name = settings_object&.tag.to_s.strip
    name.present? ? Tag.named(name).order(:id).pick(:id) : nil
  end

  # Whether a published copy speaks for this block's filter: true for a
  # block rebuilt from a copy, which then answers `listed_tag_id` without a
  # query, also when the answer is "no tag had that name". Such a block
  # lists nothing until its page is published again; the name is never
  # looked up on a copy's behalf, so a tag renamed or deleted since cannot
  # come back through a published list.
  def tag_recorded? = instance_variable_defined?(:@listed_tag_id)

  private

  # "Live" is the owner's own publication (`Publishable#live?`), as it stands
  # now: nothing moves a block from one owner to another, and a block write
  # doesn't change its owner's publication. An owner that isn't `Publishable`,
  # or is gone (destroyed in the same transaction, where its own
  # `after_commit` has the say for a page or post), counts as live: the doubt
  # is a bump.
  def bump_public_version_when_owner_live
    return if owner.respond_to?(:live?) && !owner.live?
    # A block of a record that has a copy is not what the site shows.
    return if owner.respond_to?(:published_versions) && Publishing.in_force?(owner)

    PublicSite.bump_version!
  end

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

  # The rules of a placement (sections spec §3.2), in the order a person
  # would be told them: a top-level block names no column; a container never
  # sits in a container (one level deep, decision 2); the section exists, is
  # a container and is on this block's own page (a block keeps the page as
  # its `owner`, so a section of another page would split one block between
  # two pages' permissions); and the column is one of the section's layout.
  # `[ column_count, 1 ].max` lets column 1 through for a holder that isn't
  # a container, which already has its own error above -- one message, not
  # two, for the same mistake. The database's check constraints keep the
  # pair together and the column from 1 for a write around this.
  def section_rules
    if section_id.nil?
      errors.add(:section_column, "must be blank outside a section") unless section_column.nil?
      return
    end
    return errors.add(:section, "can't hold another section") if container?

    holder = section
    return errors.add(:section, "doesn't exist") if holder.nil?

    errors.add(:section, "isn't a section") unless holder.container?
    errors.add(:section, "is on another page") unless holder.owner_type == owner_type && holder.owner_id == owner_id
    errors.add(:section_column, "isn't a column of this section") unless section_column.is_a?(Integer) && section_column.between?(1, [ holder.column_count, 1 ].max)
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

  # For a block that lists posts, or did until this save changed its type
  # (`block_type_before_last_save`; after a destroy that is its type as last
  # saved). Only a page's block is a candidate at all. Not for a block
  # destroyed WITH its page: the page's row is still there at that moment,
  # so a refresh would write the page's addresses back after they were
  # deleted; the page's own `after_destroy` says what was touched.
  def sync_listed_post_paths
    return if owner_type != Page.polymorphic_name || destroyed_by_association
    return unless definition&.capability?(:lists_posts) || BlockTypes.find(block_type_before_last_save)&.capability?(:lists_posts)

    PublicSite::Paths.refresh(pages: [ owner_id ])
  end
end
