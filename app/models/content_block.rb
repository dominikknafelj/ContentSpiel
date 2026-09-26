# One row per block on a page, in `position` order. All three block types share
# this table and are told apart by `block_type` -- the same
# single-model-plus-enum shape `Post` uses for its content types (page-tree
# design spec section 3). Which columns matter depends on the type: `body` for
# rich_text, `image` + `caption` for image, `settings` for post_list.
class ContentBlock < ApplicationRecord
  extend Mobility

  # A jsonb column holding one caption per locale; reading or writing it goes
  # through the current Mobility.locale. (`backend: :jsonb` is the app-wide
  # default set in config/initializers/mobility.rb, so it isn't repeated here --
  # same as Post's and Page's translated plain-text attributes.)
  translates :caption

  # Rich text can't live in a jsonb column -- it has attachments and its own
  # table -- so `body` uses mobility-actiontext, which keeps one
  # ActionText::RichText row per locale. This replaces `has_rich_text :body`.
  translates :body, backend: :action_text

  belongs_to :page

  enum :block_type, { rich_text: 0, image: 1, post_list: 2 }

  # Shares its name with the `image` enum value without colliding: the enum
  # contributes the class-level scope `ContentBlock.image` and the predicate
  # `#image?`, while Active Storage contributes the instance reader `#image`.
  has_one_attached :image

  validates :block_type, presence: true

  # `position` is NOT NULL with a database default, which covers a block
  # created in code but not one whose position input the admin cleared: that
  # submits an empty string, which casts to nil and reaches Postgres as a raw
  # not-null violation rendered into the form. Validated so it comes back as a
  # form error instead.
  validates :position, presence: true

  # `settings` holds a post_list's query criteria (`content_type`, `tag`,
  # `limit`). Only `content_type` is checked, and only for post_list blocks: it
  # names a Post enum value, so a typo would silently return no posts at render
  # time instead of failing in the admin.
  validate :post_list_settings_reference_a_real_content_type, if: :post_list?

  # Every row of the admin's nested block form carries the same `settings`
  # inputs, whatever the block's type, so a rich_text block would otherwise be
  # saved holding `{"content_type" => "", "tag" => "", "limit" => ""}`. Those
  # blanks are not the same as "unset": the post_list partial asks
  # `settings["limit"].present?` and hands `settings["content_type"]` straight
  # to a `where` on an enum column.
  before_validation :discard_blank_settings

  # The published posts this block is responsible for: its listing renders them
  # (newest first, trimmed to `settings["limit"]`) and its page serves a
  # permalink for each of them.
  #
  # An absent `content_type` means "every content type" -- the same reading
  # `post_list_settings_reference_a_real_content_type` below is written
  # against, and the one an editor gets by leaving the field empty in the
  # admin. It must therefore never reach `where`: `posts.content_type` is NOT
  # NULL, so `where(content_type: nil)` compiles to `content_type IS NULL` and
  # the block silently lists nothing at all.
  def listed_posts
    scope = Post.published
    content_type = settings["content_type"]
    scope = scope.where(content_type: content_type) if content_type.present?

    # Tag names are matched case-insensitively: editors type "Rails" for a tag
    # stored as "rails".
    tag = settings["tag"]
    if tag.present?
      scope = scope.where(id: PostTag.joins(:tag).where("LOWER(tags.name) = ?", tag.downcase).select(:post_id))
    end

    scope
  end

  private

  def discard_blank_settings
    self.settings = settings.to_h.compact_blank
  end

  def post_list_settings_reference_a_real_content_type
    content_type = settings["content_type"]

    # Absent means "every content type", which is a valid list.
    return if content_type.blank?
    return if Post.content_types.key?(content_type.to_s)

    errors.add(:settings, "content_type must be one of: #{Post.content_types.keys.join(', ')}")
  end
end
