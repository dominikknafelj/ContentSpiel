# Keeps a record's rows in public_paths in step with its slugs (spec §5.4),
# and refuses a slug whose resulting path another record already holds --
# as a form error, before the unique index would reject it as an exception.
#
# Both only when a URL can have changed. The including model names the
# columns its URLs are built from (`url_inputs_are`), and its `after_save`
# asks `url_inputs_changed_by_save?` first: a save that changed none of
# them -- a title, a body, a hero image, most autosaves -- reads and writes
# nothing in `public_paths`. A bare `touch` runs no save callbacks at all, so
# a block write touching its page, or a tag service touching its posts,
# never gets here.
#
# The record SAYS THAT IT WAS TOUCHED and nothing more: `PublicSite::Paths
# .refresh(pages: [self])` or `(posts: [self])`. What depends on a touched
# record is the function's to know (a page's subtree, the posts it gave an
# address to until now, the posts its list blocks can list from now on), so
# no caller works out which posts its change could have moved.
#
# What a record's URLs depend on that is NOT one of its own columns is said
# by whoever writes it, in the same way, never by this condition:
# FOR A PUBLISHED OR SCHEDULED RECORD THAT HAS A COPY, the list blocks of a
# page and the tags of a post are read from that copy, not from the rows
# (`PublicSite::Paths.canonical_pages`, drafts spec §5): the block's and the
# join row's refreshes named below then find nothing to move, and the address
# moves when the copy is taken (`Publishing::Version`'s `take!` refreshes its
# record) or, for a copy taken with a time, at the first refresh after that
# time (`Publishing::Version.settle!`). The entries below are as written for
# every other record: a draft, and one written around the services.
# - a tag's *name*, which is what a listing block's `tag` setting matches,
#   and join rows written around the association: `Tags::Rename`,
#   `Tags::Merge` and `Tags::Destroy` (a post's own tags coming and going
#   are an input of the post's save, see `Post`, and a join row added is
#   also `PostTag`'s own `after_commit`);
# - the listing blocks that give posts their page (`block_type`, `settings`'
#   `content_type` and `tag`, the owning page): `ContentBlock#
#   sync_listed_post_paths`, on every save and destroy of a listing block,
#   which names the block's page;
# - an ancestor's slug, parent or trash state, and for posts the position
#   and publication of every page on a listing page's chain: that page's own
#   save (`Page#sync_public_paths`);
# - descendants flagged around the callbacks (`Trash::Move` and
#   `Trash::Restore` write a branch's members with `update_all`): the
#   branch root's own save, last, whose `trashed_at` is an input;
# - siblings renumbered by `Page::TreeRanking#place_among_siblings`
#   (`update_columns`): the moved page's save, whose requested `position` is
#   an input; the relative order of every other page is unchanged;
# - the enabled languages: `Locales::Enable` refreshes everything, `Locales::
#   Disable` deletes the language's rows (the default language is no input:
#   it decides how a link is written, not which rows exist);
# - time: a scheduled page or post going live writes nothing; its published
#   copy is due from that moment and the first refresh after it settles it
#   (`Publishing::Version.settle!`).
# `test/models/public_site/paths_test.rb` ("every write path leaves
# public_paths equal to a full rebuild") runs one step per entry of both
# lists and compares the table with `PublicSite::Paths.rebuild!` after each;
# a new input, or a new write path around the callbacks, belongs in it. And
# `test/lib/public_paths_entry_test.rb` holds that every one of them goes
# through `refresh`.
module HasPublicPaths
  extend ActiveSupport::Concern

  included do
    has_many :public_paths, as: :record, dependent: :delete_all # version: none (the destroyed record's own after_commit bumps when it was live)
    validate :public_paths_are_available

    # The columns this model's URLs are built from, set by `url_inputs_are`.
    class_attribute :url_input_names, instance_writer: false, default: [].freeze

    # `before_save`, not `after_save`: by the time a `Page`'s own
    # `after_save` runs, closure_tree's has reloaded the record and
    # cleared its dirty flags, and `Page::TreeRanking#place_among_siblings`
    # has written the dense `position` over the one that was asked for. So
    # the question is asked while the changes are still pending and the
    # answer kept for `url_inputs_changed_by_save?` (the same reason
    # `TreeRanking#remember_requested_position` is a `before_save`).
    before_save :remember_url_inputs_change
  end

  class_methods do
    def url_inputs_are(*names)
      self.url_input_names = names.map(&:to_s).freeze
    end
  end

  def full_path(locale)
    PublicSite::Paths.current_path(self, locale)
  end

  # The values this record's URLs are built from, as they stand in memory:
  # `{ column => value }`, a translated column as its whole `{ locale =>
  # value }` hash, since a slug is an input in every language at once.
  def url_inputs
    url_input_names.index_with { |name| read_attribute(name).then { |value| value.is_a?(Hash) ? value.dup.freeze : value } }.freeze
  end

  # Whether saving this record now would change one of them -- always, for a
  # new record, which has no URLs yet. Asked of Active Record's own pending
  # changes, so it is only meaningful *before* the row is written (a
  # validation, a `before_save`); a jsonb column changed in place counts, and
  # so does a column forced dirty with `_will_change!` (`Trash::Restore#
  # keep_rank` asks for the same `position` again that way).
  def url_inputs_changed?
    new_record? || url_input_names.any? { |name| will_save_change_to_attribute?(name) }
  end

  private

  def remember_url_inputs_change
    @url_inputs_changed_by_save = url_inputs_changed?
  end

  # For the including model's `after_save`: whether the save that just ran
  # changed a URL input. True when nothing was remembered (a callback chain
  # that skipped the `before_save`), so the doubt is a sync, never a skip.
  def url_inputs_changed_by_save?
    @url_inputs_changed_by_save != false
  end

  # A path already held by *another* record's current row is a validation
  # error (spec §5.2), reported against the slug that produces it -- the same
  # way `LocalizedSlug`'s own sibling-slug check attributes a collision to the
  # locale it clashes in, so the admin form marks the tab that actually needs
  # editing rather than a generic `:base` error nobody can act on.
  #
  # This is the guard against the two-pages-one-URL collision `Page`'s old
  # `cached_paths`/`build_path` allowed by accident (a blank non-root slug
  # collapsing onto its parent's path): `PublicSite::Paths.compute` already
  # returns nil rather than a borrowed path for that case, and `taken` below
  # additionally catches two *different*, non-blank slugs that would still
  # resolve to the same address.
  #
  # Skipped for a stored record none of whose URL inputs is about to change:
  # its paths are the ones it already holds, so it cannot newly clash, and a
  # title-only save computes no path and asks `public_paths` nothing.
  #
  # What this cannot see is an address that follows from a PUBLISH: a tag
  # made by the very save that carries it has no id yet, and a published
  # post is judged by its copy's tags, not by the ones about to be
  # published. Those are refused when the copy is taken, which rolls the
  # publish back (`Publishing::AddressTaken`); this stays the check that
  # marks the slug field before anything is written.
  def public_paths_are_available
    return unless url_inputs_changed?

    paths = PublicSite::Paths.compute(self).compact
    return if paths.empty?

    taken = PublicPath.current.where(path: paths.values.uniq)
      .where.not(record_type: self.class.polymorphic_name, record_id: id).pluck(:locale, :path).to_set
    paths.select { |locale, path| taken.include?([ locale.to_s, path ]) }.each do |locale, path|
      errors.add(Mobility.normalize_locale_accessor(:slug, locale), :taken,
        message: "gives the address #{path}, which is already taken in #{locale.upcase}")
    end
  end
end
