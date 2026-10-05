class Post < ApplicationRecord
  extend Mobility
  include LocalizedSlug
  include Publishable
  include HasPublicPaths
  include Trashable

  # A post with no slug in some enabled locale would have no URL there at
  # all (see `LocalizedSlug#slug_present_in_every_enabled_locale`, registered
  # by `localized_slug scope: :content_type` below -- unconditional here,
  # unlike `Page`'s `generates_slugs?`, since a post has no root-page
  # equivalent that's exempt).
  localized_slug scope: :content_type

  # `title`, `slug` and `excerpt` are jsonb columns holding one value per
  # locale; reading or writing them goes through the current Mobility.locale.
  translates :title, :slug, :excerpt

  # `body_document(locale:)`/`assign_body` over the jsonb `body` column
  # (design spec §3.1). Included after `extend Mobility` above -- it calls
  # `translates` itself.
  include HasRichTextBody

  # Which version of the original each translation was saved against
  # (translation helpers spec §3.2), plus the content type's own
  # `translated: true` fields. Never `slug`: it's generated per language.
  include Translations::Tracker
  include TitleSearch
  tracks_translations schema: :fields

  has_many :post_tags, dependent: :destroy
  # The callbacks note that the set of tags changed, for the URL sync below:
  # a tag is one of the things a post's URL is built from, and no column of
  # this row says that one came or went.
  has_many :tags, through: :post_tags, after_add: :note_tags_changed, after_remove: :note_tags_changed

  has_many :post_relations, dependent: :destroy
  has_many :related_posts, through: :post_relations

  # Nullable (design spec §3.2): not every post has an author, and a user
  # delete nullifies this column rather than orphaning the post or blocking
  # the delete -- "own" (the `posts.*` grant scope keyed to this column,
  # `AccessControl::Grant#scope_own?`) then simply stops matching for
  # anyone, which is fine, not an error. `Posts::Save` (a later task) sets
  # it to the acting user on create.
  belongs_to :author, class_name: "User", optional: true

  # PostRelation holds two FKs into posts. `post_relations` only covers the
  # `post_id` side; without this the `related_post_id` side is left dangling
  # and destroying the post raises ActiveRecord::InvalidForeignKey.
  has_many :inverse_post_relations, class_name: "PostRelation",
    foreign_key: :related_post_id, dependent: :destroy, inverse_of: :related_post

  # A plain string, checked against the `ContentTypes` registry (open-types
  # spec §4.2) rather than a closed enum -- `content_type_is_registered`
  # below turns an unrecognised value (e.g. "nope" arriving from
  # `Posts::Save`'s untrusted `attributes:`) into a validation error, and so
  # an `ApplicationService::Result#failure`, the same job the old enum's
  # `validate: true` did with its `ArgumentError`-turned-validation-error.
  validates :content_type, presence: true
  validate :content_type_is_registered

  # Delegates to the type's own `ContentModel::FieldSet` (built from its
  # field schema) rather than a hand-written check -- every content type's
  # `fields` are validated the same way, not just resume_entry's. Resume
  # entries' structured fields (`ROLE_TYPES`, `company`, `role`, `role_type`,
  # `start_date`, `end_date`) used to live here as a `store_accessor`; they
  # now live in `ContentTypes::ResumeEntry`'s own field schema instead, still
  # over this same `metadata`/`translated_metadata` pair.
  validate :fields_are_valid

  # "Titled" means *some* locale has a title, not "the locale that happens to
  # be ambient when this record is saved" -- a post may legitimately exist in
  # German before it is ever written in English, or vice versa (see the
  # pinned test "a title in a non-default locale satisfies the presence
  # requirement"). Before this task, `validates :title, presence: true` got
  # this right by accident: Mobility's own global fallback plugin meant the
  # plain reader returned *some* locale's title regardless of which one was
  # ambient. Now that plain readers read literally (config/initializers
  # /mobility.rb), the same `validates :title, presence: true` would instead
  # reject a fully-titled post just because it was saved inside a
  # `Mobility.with_locale(:de)` block for an unrelated German-only edit -- so
  # this reads the raw jsonb hash directly rather than through Mobility,
  # sidestepping the ambient locale entirely.
  validate :title_present_in_any_locale

  # Keeps `public_paths` in step with this post's canonical listing page and
  # slug (spec §5.4) -- the same duty `Page#sync_public_paths` performs for
  # pages, just without a subtree to cascade into: a post has no descendants
  # of its own, so `PublicSite::Paths.sync` (not `sync_subtree`) is enough.
  # Only for a save that changed one of the post's URL inputs (a new post
  # always; see `HasPublicPaths`):
  # - `slug`, in every language: its own segment;
  # - `content_type`: which listing blocks list it at all, and whether it
  #   has a URL (an unregistered type has none);
  # - `trashed_at`: a trashed post has no URL;
  # - `published_at`: no part of the path today (the resolver, not the
  #   path, keeps a draft off the site), kept as an input so that nothing
  #   about publication has to be re-argued here when that changes.
  #
  # And its tags, which are no column of this row: a tag-filtered listing
  # block lists a post by the tags it carries, so a tag gained or lost can
  # move the post to another listing page. `has_many :through` writes the
  # join rows directly and at once, and takes them away with a plain
  # `DELETE` that runs no `PostTag` callback -- so `post.tags = [...]`
  # (`Posts::Save#assign_tags`) dropping a tag is seen by nothing but the
  # association's own `after_remove`, which is why the association notes
  # every change (`note_tags_changed`) and the save that follows counts it
  # as a changed input. A tag *added* is also synced by `PostTag`'s own
  # `after_commit`, with or without a save of the post; a tag removed
  # through the association with no save of the post afterwards is synced
  # by nothing until the next sync that reaches the post.
  url_inputs_are :slug, :content_type, :published_at, :trashed_at
  after_save :sync_public_paths

  # The columns, and the ids of the tags the post carries (a query unless
  # the association is loaded; nothing on a save path reads this).
  def url_inputs
    super.merge("tag_ids" => tag_ids.sort.freeze).freeze
  end

  def url_inputs_changed?
    super || @tags_changed == true
  end

  def all_related_posts
    forward_ids = PostRelation.where(post_id: id).select(:related_post_id)
    backward_ids = PostRelation.where(related_post_id: id).select(:post_id)
    Post.where(id: forward_ids).or(Post.where(id: backward_ids))
  end

  # `ActiveModel::Validations` aliases this to `#send` by default, which
  # chokes on the dotted paths `fields_are_valid` below adds errors under
  # (`fields.company` is not a method) -- generating an error's full message
  # reads the attribute's current value through this. Same fix as
  # `ContentModel::FieldSet::Base`'s own override, for the same reason.
  def read_attribute_for_validation(key)
    respond_to?(key) ? public_send(key) : nil
  end

  # This post's registered content type, or nil for a stored `content_type`
  # that isn't (or is no longer) registered -- e.g. a removed plugin's type.
  # `find`, not `fetch`: an unknown stored type must never raise here, since
  # this is read from render and path-sync boundaries that a stale record
  # must not be able to 500 (global constraints).
  def definition = ContentTypes.find(content_type)

  # The content type's `ContentModel::FieldSet` instance over this post's
  # `metadata`/`translated_metadata`, or nil when `content_type` isn't
  # registered (there is no schema to build one from).
  def fields(locale: I18n.locale, fallback: false)
    definition&.field_set&.new(metadata, translated_metadata, locale:, fallback:)
  end

  # Casts and validates `hash` against the content type's schema, then writes
  # the result back onto `metadata`/`translated_metadata`. Does nothing for
  # an unregistered type -- there is no schema to assign against, and
  # `content_type_is_registered` is what reports that instead.
  def assign_fields(hash, locale:)
    object = fields(locale:) or return

    # A key assigned again starts clean: an earlier rejection of it must not
    # outlive a later, valid value.
    hash.to_h.each_key { |name| rejected_field_inputs.delete(name.to_s) }
    object.assign(hash)
    object.rejected_inputs.each { |name| rejected_field_inputs[name] = "must use the form yyyy-mm-dd" }
    self.metadata = object.untranslated_hash
    self.translated_metadata = object.all_translations.merge(locale.to_s => object.translated_hash).compact_blank
  end

  private

  def note_tags_changed(_tag)
    @tags_changed = true
  end

  def sync_public_paths
    return unless url_inputs_changed_by_save?

    PublicSite::Paths.sync(self)
    @tags_changed = false
  end

  # Raw jsonb hash, not the Mobility reader: see the comment above
  # `validate :title_present_in_any_locale`.
  def title_present_in_any_locale
    errors.add(:title, :blank) if read_attribute(:title).to_h.values.all?(&:blank?)
  end

  def content_type_is_registered
    errors.add(:content_type, "isn't a registered content type") if content_type.present? && ContentTypes.find(content_type).nil?
  end

  # `locale: Locales.default`, not `fields`'s own ambient-`I18n.locale`
  # default: a required translated field is always written at least at
  # `Locales.default` (`Posts::Save` assigns top-level `fields` there), so checking
  # `required` against whatever `I18n.locale` a request happens to leave
  # ambient -- unrelated to the site's own default -- would reject a post
  # that saved correctly the moment those two locales disagree.
  def fields_are_valid
    object = fields(locale: Locales.default) or return
    # Text a date field was handed that isn't `yyyy-mm-dd` (`#assign_fields`)
    # never reached the stored value, so `object` can't see it: reported here.
    # Every `fields.*` error reads "<label> <message>" through
    # `.human_attribute_name` below, so it names its field wherever it shows
    # (the editor's slot, the flash, MCP).
    rejected_field_inputs.each { |name, message| errors.add("fields.#{name}", :invalid, message: message) }
    return if object.valid?

    object.errors.each { |error| errors.add("fields.#{error.attribute}", error.type, message: error.message) }
  end

  # How a typed field's error names it: `fields.company` -> "Company",
  # `fields.speakers.0.name` -> "Speakers, row 1: name" (a `groups` row),
  # `fields.address.street` -> "Address: street" (a `group`). Rails would
  # otherwise print the dotted path ("Fields speakers 0 name ...").
  def self.human_attribute_name(attribute, options = {})
    parts = attribute.to_s.split(".")
    return super unless parts.first == "fields" && parts.size > 1

    _, field, *rest = parts
    label = field.humanize
    return label if rest.empty?

    row = rest.first.match?(/\A\d+\z/) ? rest.shift.to_i + 1 : nil
    sub = rest.join(" ").humanize.downcase
    row ? "#{label}, row #{row}: #{sub}" : "#{label}: #{sub}"
  end

  # field name => message, for input a typed field couldn't be built from.
  def rejected_field_inputs = (@rejected_field_inputs ||= {})
end
