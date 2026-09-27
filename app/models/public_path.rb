# One public URL of a page or post in one language (spec §5.1). `current`
# rows are live addresses; the rest are addresses the record used to have,
# kept so old links 301 to where the record lives now. Written only by
# PublicSite::Paths -- never by hand -- so the table always matches the
# slugs and tree it is derived from.
class PublicPath < ApplicationRecord
  belongs_to :record, polymorphic: true

  scope :current, -> { where(current: true) }
  scope :redirects, -> { where(current: false) }
end
