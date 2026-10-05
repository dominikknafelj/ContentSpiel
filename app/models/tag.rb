class Tag < ApplicationRecord
  has_many :post_tags, dependent: :destroy
  has_many :posts, through: :post_tags

  # Long enough for any real tag, short enough that a pasted sentence is
  # refused rather than becoming a tag (the chip input marks it at once).
  MAX_NAME_LENGTH = 50

  # A tag's name is printed on the posts that carry it and is what a listing
  # block's `tag` setting matches, so a rename or a delete moves the public
  # content version (`PublicSite`, technical cleanup spec §4.8), whether or
  # not a live post carries the tag. A new tag is on no page until a join row
  # says so (`PostTag`).
  after_commit(on: %i[update destroy]) { PublicSite.bump_version! }

  validates :name, presence: true, uniqueness: true, length: { maximum: MAX_NAME_LENGTH }
end
