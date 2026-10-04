class Tag < ApplicationRecord
  has_many :post_tags, dependent: :destroy
  has_many :posts, through: :post_tags

  # Long enough for any real tag, short enough that a pasted sentence is
  # refused rather than becoming a tag (the chip input marks it at once).
  MAX_NAME_LENGTH = 50

  validates :name, presence: true, uniqueness: true, length: { maximum: MAX_NAME_LENGTH }
end
