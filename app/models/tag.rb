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

  # Every match on a tag's name is case-insensitive, by `LOWER(tags.name)` on
  # both sides: names are stored lowercase today, but one stored with a capital
  # (an old row, a write around the model) must still be found by the name an
  # editor types or a picker shows. These scopes are the only places that
  # comparison is spelled; a caller hands over the text as typed.

  # The tag(s) of exactly this name, whatever the case.
  scope :named, ->(name) { where("LOWER(tags.name) = ?", name.to_s.downcase) }
  # Every tag but the ones of these names, whatever the case.
  scope :not_named, ->(names) { where.not("LOWER(tags.name) IN (?)", Array(names).map { |name| name.to_s.downcase }) }
  # The tags whose name contains this text; a typed `%` or `_` is a character
  # to find, not a wildcard (`sanitize_sql_like`).
  scope :name_containing, ->(text) { where("LOWER(tags.name) LIKE ?", "%#{sanitize_sql_like(text.to_s.downcase)}%") }
  # Ordering: the tags whose name STARTS with this text ahead of the rest.
  scope :name_starting_first, ->(text) {
    order(Arel.sql(sanitize_sql_array([ "(LOWER(tags.name) LIKE ?) DESC", "#{sanitize_sql_like(text.to_s.downcase)}%" ])))
  }
  # Ordering: alphabetical, capitals and small letters together.
  scope :by_name, -> { order(Arel.sql("LOWER(tags.name) ASC")) }

  # Each tag with `posts_count`, the number of the given posts (a relation --
  # the posts a viewer may read) that carry it: a correlated subquery, so the
  # tag list stays one query. `most_used_first` orders by it.
  scope :with_posts_count, ->(posts) {
    carried = posts.joins(:post_tags).where("post_tags.tag_id = tags.id").select("COUNT(*)")
    select(Arel.sql("(#{carried.to_sql}) AS posts_count"))
  }
  scope :most_used_first, -> { order(Arel.sql("posts_count DESC")) }

  # `{ tag id => how many of the given posts carry it }` for these tag ids, in
  # one grouped query; a tag none of them carries has no entry.
  def self.posts_counts(posts, ids)
    posts.joins(:post_tags).where(post_tags: { tag_id: ids }).group("post_tags.tag_id").count
  end
end
