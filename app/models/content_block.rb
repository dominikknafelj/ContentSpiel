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

  # `settings` holds a post_list's query criteria (`content_type`, `tag`,
  # `limit`). Only `content_type` is checked, and only for post_list blocks: it
  # names a Post enum value, so a typo would silently return no posts at render
  # time instead of failing in the admin.
  validate :post_list_settings_reference_a_real_content_type, if: :post_list?

  private

  def post_list_settings_reference_a_real_content_type
    content_type = settings["content_type"]

    # Absent means "every content type", which is a valid list.
    return if content_type.blank?
    return if Post.content_types.key?(content_type.to_s)

    errors.add(:settings, "content_type must be one of: #{Post.content_types.keys.join(', ')}")
  end
end
