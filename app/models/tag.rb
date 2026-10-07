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
  # comparison is spelled (`lowered_name`); a caller hands over the text as
  # typed.

  # The tag(s) of exactly this name, whatever the case.
  scope :named, ->(name) { where(lowered_name.eq(name.to_s.downcase)) }
  # Every tag but the ones of these names, whatever the case. With no name at
  # all it is no tag at all, not every tag -- what `NOT (... IN (NULL))`, the
  # condition this used to be, answered; the one caller never passes an empty
  # list.
  scope :not_named, ->(names) {
    names = Array(names).map { |name| name.to_s.downcase }
    names.empty? ? none : where.not(lowered_name.in(names))
  }
  # The tags whose name contains this text; a typed `%` or `_` is a character
  # to find, not a wildcard (`SqlNodes.like_pattern`).
  scope :name_containing, ->(text) { where(SqlNodes.like(lowered_name, SqlNodes.like_pattern(text.to_s.downcase))) }
  # Ordering: the tags whose name STARTS with this text ahead of the rest
  # (`(LOWER(name) LIKE 'text%') DESC`: true sorts before false).
  scope :name_starting_first, ->(text) {
    order(Arel::Nodes::Grouping.new(SqlNodes.like(lowered_name, SqlNodes.like_pattern(text.to_s.downcase, prefix: true))).desc)
  }
  # Ordering: alphabetical, capitals and small letters together.
  scope :by_name, -> { order(lowered_name.asc) }

  # Each tag with `posts_count`, the number of the given posts (a relation --
  # the posts a viewer may read) that carry it: a correlated subquery, so the
  # tag list stays one query. `most_used_first` orders by it.
  scope :with_posts_count, ->(posts) {
    carried = posts.joins(:post_tags).where(PostTag.arel_table[:tag_id].eq(arel_table[:id])).select(Arel.star.count)
    select(Arel::Nodes::Grouping.new(carried.arel.ast).as("posts_count"))
  }
  # `posts_count` is the name `with_posts_count` gave its expression, not a
  # column of `tags`, so it is ordered by unqualified.
  scope :most_used_first, -> { order(Arel::Nodes::UnqualifiedColumn.new(arel_table[:posts_count]).desc) }

  # `LOWER(tags.name)`.
  def self.lowered_name = arel_table[:name].lower

  # `{ tag id => how many of the given posts carry it }` for these tag ids, in
  # one grouped query; a tag none of them carries has no entry.
  def self.posts_counts(posts, ids)
    posts.joins(:post_tags).where(post_tags: { tag_id: ids }).group(post_tags: :tag_id).count
  end
end
