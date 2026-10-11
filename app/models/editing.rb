# Live refresh and edit reservations (live-editing spec; the look is its
# handoff). Two things live here.
#
# LIVE REFRESH: what someone saves appears in every other open editor of that
# page or post. `Editing::Signals` hears the audit log's after-commit
# notification and says, on the record's stream, THAT something changed (a
# kind, ids, a reason); the editor fetches the part through the read scope.
#
# RESERVATIONS: a block, a page's settings or a post that someone is changing
# is theirs for `HOLD` after their last saved change (`Editing::Reservation`),
# read-only for everyone else, who can take it over (`Editing::TakeOver`).
#
# A RESERVATION IS NOT CONTENT. Claiming, renewing and releasing are not
# `ApplicationService`s and are not audited (as presence's marks are not):
# they write only their own row, never the record, and they would flood the
# log. Taking over is the one audited write. Nothing here knows notes or
# presence, and the content side does not know this module: the only thing a
# content service does for it is name a deleted block's page in the event it
# already records.
module Editing
  # How long a reservation lasts after its holder's last saved change.
  HOLD = 2.minutes
  # How long a take-over waits for the holder's tab to hand over.
  PASS_OVER = 5.seconds
  # How long "Taken over by ..." and "Updated by ..." stay on screen.
  NOTICE = 6.seconds
  # The sweep's age. Nothing depends on it: every read ignores a row after HOLD.
  SWEEP_AFTER = 10.minutes

  # What a request names with `block_id`: that block of this page, or the
  # record itself (a page's settings, a post). Nil for a block that is not
  # this record's: the caller answers 404.
  def self.subject_of(record, block_id)
    return record if block_id.blank?
    return unless record.is_a?(Page)

    id = block_id.to_s[/\A\d{1,18}\z/] or return
    record.content_blocks.find_by(id:)
  end

  # The subject's name in the page (`data-editing-subject`) and in a request.
  def self.key(subject) = subject.is_a?(ContentBlock) ? "block-#{subject.id}" : "record"

  # What a unit or part of an editor says about the content it shows
  # (`data-editing-version`): a block's `updated_at`, a page's
  # `settings_changed_at` (the settings form's own base), a post's
  # `updated_at`, in microseconds. A catch-up (`editing/merge`, `onlyChanged`)
  # leaves a clean unit alone when the answer's version is the same. EVERY
  # version is written through this method, so that what else a unit's look
  # depends on (a reservation's state, later) is added in one place.
  # It does NOT cover what a unit shows of other records or of the viewer
  # (their rights, a library image's file, a tag's name, an ancestor's slug):
  # a catch-up leaves those as they are until the next signal or a reload.
  def self.version(subject)
    stamp = subject.is_a?(Page) ? subject.settings_changed_at : subject.updated_at
    stamp && (stamp.to_r * 1_000_000).to_i.to_s
  end
end
