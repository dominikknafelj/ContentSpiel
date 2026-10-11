# `published_at` doubles as draft/schedule flag (spec §10.4): nil is a draft,
# a future time is scheduled, now or past is live. The `published` scope is
# what the public site serves; a beginless range compiles to
# `published_at <= now()`, which drops both NULLs and future dates.
module Publishable
  extend ActiveSupport::Concern

  STATUSES = %w[draft scheduled live].freeze

  included do
    scope :published, -> { where(published_at: ..Time.current) }
    # Waiting for its time: strictly later than now, so a draft (NULL) and a
    # record going live this very instant are both left out -- `published`'s
    # exact complement among the records that have a time at all.
    scope :scheduled, -> { where(arel_table[:published_at].gt(Time.current)) }

    # The public content version (`PublicSite`, technical cleanup spec §4.8)
    # moves with every committed change to a record that is live before or
    # after it. "Before" has to be noted while the change is still pending:
    # by `after_commit` a `Page` has been reloaded by closure_tree's own
    # `after_save`, which clears `saved_change_to_published_at`, and a
    # transaction may hold several saves of one record, of which
    # `after_commit` sees only the last.
    before_save :note_live_before_change
    before_destroy :note_live_before_change
    after_commit :bump_public_version_when_live
    after_rollback :forget_live_before_change

    # The copies the public site has shown of this record (`Publishing`).
    # Deleted with it, around their callbacks: they have none.
    has_many :published_versions, class_name: "Publishing::Version", as: :record, dependent: :delete_all # version: none (the destroyed record's own after_commit bumps when it was live)
  end

  # The copy a record REBUILT by `Publishing::Snapshot` was made from; nil on
  # a row. A public reader that needs to know which it holds asks this.
  attr_accessor :published_version

  def status
    if published_at.nil?
      "draft"
    elsif published_at > Time.current
      "scheduled"
    else
      "live"
    end
  end

  def live?
    status == "live"
  end

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

  def publish_now!
    update!(published_at: Time.current)
  end

  def unpublish!
    update!(published_at: nil)
  end

  private

  # `published_at_in_database`: the stored value this save or destroy
  # replaces. Or-ed, never overwritten, so an unpublish followed by another
  # save in the same transaction still counts as "was live".
  def note_live_before_change
    before = published_at_in_database
    @live_before_change ||= before.present? && before <= Time.current
  end

  def forget_live_before_change
    @live_before_change = nil
  end

  def bump_public_version_when_live
    PublicSite.bump_version! if live_before_or_after_save?
  ensure
    forget_live_before_change
  end
end
