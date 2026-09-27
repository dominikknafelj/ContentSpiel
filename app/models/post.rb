class Post < ApplicationRecord
  extend Mobility
  include LocalizedSlug
  include Publishable
  include HasPublicPaths

  # A post with no slug in some enabled locale would have no URL there at
  # all (see `LocalizedSlug#slug_present_in_every_enabled_locale`, registered
  # by `localized_slug scope: :content_type` below -- unconditional here,
  # unlike `Page`'s `generates_slugs?`, since a post has no root-page
  # equivalent that's exempt).
  localized_slug scope: :content_type

  # `title`, `slug` and `excerpt` are jsonb columns holding one value per
  # locale; reading or writing them goes through the current Mobility.locale.
  translates :title, :slug, :excerpt

  # Rich text can't live in a jsonb column -- it has attachments and its own
  # table -- so `body` uses mobility-actiontext, which keeps one
  # ActionText::RichText row per locale. This replaces `has_rich_text :body`.
  translates :body, backend: :action_text

  has_many :post_tags, dependent: :destroy
  has_many :tags, through: :post_tags

  has_many :post_relations, dependent: :destroy
  has_many :related_posts, through: :post_relations

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
  # Unconditional for the same reason `Page`'s callback is: `slug` is a
  # Mobility jsonb attribute, so there's no per-locale `saved_change_to?` to
  # narrow this with, and guessing wrong leaves a post unreachable at its own
  # URL.
  #
  # A tag gained or lost through `post.tags << tag`/`tag.destroy` doesn't
  # touch this row at all -- `has_many :through` writes `PostTag` directly --
  # so `PostTag`'s own `after_commit` callback is what re-syncs a post whose
  # *tag-filtered* canonical page depends on a change this callback never
  # sees.
  after_save { PublicSite::Paths.sync(self) }

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

    object.assign(hash)
    self.metadata = object.untranslated_hash
    self.translated_metadata = object.all_translations.merge(locale.to_s => object.translated_hash).compact_blank
  end

  # The seam `Avo::Resources::Post`'s typed-fields tool (`app/avo/
  # resource_tools/typed_fields.rb`) writes through: its `extra_params`
  # entry (`fields: {}`) makes Avo call `assign_attributes(fields: hash)` on
  # submit, same as any other attribute, and `assign_attributes` just calls
  # this. `locale: Locales.default` because that tool has no locale switcher
  # of its own yet (unlike `title`/`body`, which get one via Mobility's
  # tabs) -- a translated content-type field isn't editable in Avo until
  # sub-project 3 gives it one, the same limit a block's own group/groups
  # settings fields are under (see `_typed_fields.html.erb`).
  def fields=(hash)
    assign_fields(hash, locale: Locales.default)
  end

  private

  # Raw jsonb hash, not the Mobility reader: see the comment above
  # `validate :title_present_in_any_locale`.
  def title_present_in_any_locale
    errors.add(:title, :blank) if read_attribute(:title).to_h.values.all?(&:blank?)
  end

  def content_type_is_registered
    errors.add(:content_type, "isn't a registered content type") if content_type.present? && ContentTypes.find(content_type).nil?
  end

  def fields_are_valid
    object = fields or return
    return if object.valid?

    object.errors.each { |error| errors.add("fields.#{error.attribute}", error.type, message: error.message) }
  end
end
