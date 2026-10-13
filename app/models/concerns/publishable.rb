# `published_at` doubles as draft/schedule flag (spec §10.4): nil is a draft,
# a future time is scheduled, now or past is live. The `published` scope is
# what the public site serves; a beginless range compiles to
# `published_at <= now()`, which drops both NULLs and future dates.
module Publishable
  extend ActiveSupport::Concern

  STATUSES = %w[draft scheduled live].freeze

  # Columns whose change no page shows: a save that changes only these, or
  # only content a copy holds, changes nothing public where a copy is shown.
  BOOKKEEPING = %w[updated_at settings_changed_at unpublished_changes_at translation_sources translation_original_changed_at].freeze

  included do
    scope :published, -> { where(published_at: ..Time.current) }
    # Waiting for its time: strictly later than now, so a draft (NULL) and a
    # record going live this very instant are both left out -- `published`'s
    # exact complement among the records that have a time at all.
    scope :scheduled, -> { where(arel_table[:published_at].gt(Time.current)) }
    # The records `unpublished_changes?` is true of, as a relation: a time
    # and a mark.
    scope :with_unpublished_changes, -> { where.not(published_at: nil).where.not(unpublished_changes_at: nil) }

    # The public content version (`PublicSite`, technical cleanup spec §4.8)
    # moves with every committed change to a record that is live before or
    # after it. "Before" has to be noted while the change is still pending:
    # by `after_commit` a `Page` has been reloaded by closure_tree's own
    # `after_save`, which clears `saved_change_to_published_at`, and a
    # transaction may hold several saves of one record, of which
    # `after_commit` sees only the last.
    before_save :note_live_before_change
    # The mark that the rows have moved on from what is published
    # (`unpublished_changes_at`, drafts spec §4.4). After the save, so that
    # `saved_changes` says what it wrote; a save marks, and a `touch` (which
    # runs no save callback: every block write that changes something touches its page, a post is
    # touched for its tags) marks around the callbacks.
    after_save :note_unpublished_changes
    after_touch :note_unpublished_changes_on_touch
    before_destroy :note_live_before_change
    # A destroy has no `changed`, and it is always immediate.
    before_destroy { @immediate_change = true }
    after_commit :bump_public_version_when_live
    after_rollback :forget_live_before_change

    # The copies the public site has shown of this record (`Publishing`).
    # Deleted with it, around their callbacks: they have none.
    has_many :published_versions, class_name: "Publishing::Version", as: :record, dependent: :delete_all # version: none (the destroyed record's own after_commit bumps when it was live)
  end

  # The copy a record REBUILT by `Publishing::Snapshot` was made from; nil on
  # a row. A public reader that needs to know which it holds asks this.
  attr_accessor :published_version

  # "draft", "scheduled" or "live": `Publishing::State`'s, which is the one
  # place the time is compared with the clock.
  def status = Publishing::State.of(self).status

  def live?
    status == "live"
  end

  # Whether this record's rows have moved on from what is published: the
  # cheap read every list makes, a column and no comparison. A draft has no
  # unpublished changes, whatever mark it kept from before. It is
  # `Publishing::State#changes?`, asked of the record
  # (`test/values/publishing/state_test.rb` holds that the two agree); the
  # scope below is the same fact in SQL.
  def unpublished_changes? = Publishing::State.of(self).changes?

  # Whether this record's own publication time is in the past on either side
  # of the change being committed (or, asked outside one, right now): what
  # decides that a write to it can have changed published output. Its own
  # time only -- not its ancestors' and not the trash -- so a live page under
  # a draft parent, or a live post in the trash, answers true: more bumps than
  # strictly needed, never fewer. A scheduled record answers false until its
  # time has passed; that moment is covered by `PublicSite.content_version`'s
  # own publication-time lookups, not by a write.
  #
  # True also after a `touch`, which runs neither `before_save` nor any dirty
  # tracking: a touched record's publication is unchanged, so `live?` is the
  # whole answer.
  def live_before_or_after_save?
    @live_before_change == true || live?
  end

  # A touch that moves `updated_at` (an open form goes stale) and is no
  # change to what a copy holds.
  def touch_without_mark
    @touched_without_mark = true
    touch
  ensure
    @touched_without_mark = nil
  end

  private

  # `published_at_in_database`: the stored value this save or destroy
  # replaces. Or-ed, never overwritten, so an unpublish followed by another
  # save in the same transaction still counts as "was live".
  def note_live_before_change
    before = published_at_in_database
    @live_before_change ||= before.present? && before <= Time.current
    # What is immediate (drafts spec D7): the slug, the tree, `published_at`,
    # the trash, a post's type; a new record. Or-ed across the saves of one
    # transaction, like the line above.
    @immediate_change ||= new_record? || (changed - Publishing.content_columns(self) - BOOKKEEPING).any?
  end

  # A column a copy holds has changed on a record, or a touch says a write
  # beside it did. The mark is set by `Publishing.note_change`, whose UPDATE
  # asks THE ROW (`published_at IS NOT NULL`), never this object: an object
  # loaded before a colleague published still marks, and one loaded after an
  # unpublish does not. The save that publishes or schedules for the first
  # time (or a new record) is not a change waiting to be published: its copy
  # is taken from these very rows. The mark may be set when the net
  # difference is nothing (typed and typed back): `Publishing::Changes` then
  # finds none. It moves neither `updated_at` nor a page's settings base.
  def note_unpublished_changes
    return if previously_new_record? || (saved_change_to_published_at? && published_at_before_last_save.nil?)

    Publishing.note_change(self) if (saved_changes.keys & Publishing.content_columns(self)).any?
  end

  # A touch is how a write beside the record says it changed: every block
  # write touches its page, and a post is touched for its tags. `touch` runs
  # no save callback, so the mark is written here. A touch that is no
  # change to a copy (`touch_without_mark`: a post's related posts, which no
  # copy holds) says so.
  def note_unpublished_changes_on_touch
    Publishing.note_change(self) unless @touched_without_mark
  end

  def forget_live_before_change
    @live_before_change = nil
    @immediate_change = nil
  end

  # The version moves for a committed change the public can see. With a copy
  # (`Publishing`), that is only what is immediate: the copy's content does
  # not change when the rows do, and taking the next copy bumps
  # (publishing the changes), or, for a change with a time of its own,
  # the part of `PublicSite.content_version` that follows the copies by the
  # clock. Without a copy in force the rows are what the site shows, and every write
  # moves it, as it always did. A `touch` (a block's write) notes nothing, so
  # it moves the version only without a copy.
  def bump_public_version_when_live
    PublicSite.bump_version! if live_before_or_after_save? && (@immediate_change || !Publishing.in_force?(self))
  ensure
    forget_live_before_change
  end
end
