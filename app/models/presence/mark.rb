module Presence
  # One person's browser tab on one record: `state` ("here", or "away" when
  # the tab is hidden or idle), `seen_at` (the last time the tab said it was
  # still there) and `arrived_at` (when this tab first came, kept when the
  # same tab subscribes again). The unique index is user, record and tab.
  #
  # EVERY METHOD IS ONE STATEMENT and writes nothing but its own row: no
  # `touch`, nothing on the record, no audit event, no content version. There
  # are no callbacks, and the row is never saved through the model; `record`
  # is declared so that a query can say `where(record:)`, and it is optional
  # because a record's trashing or purging leaves its rows to expire
  # (`fresh`, `Presence::Sweep`).
  class Mark < ApplicationRecord
    self.table_name = "presence_marks"

    belongs_to :user
    belongs_to :record, polymorphic: true, optional: true

    # What every read goes through: a row seen in the last STALE_AFTER. The
    # cut-off is worked out here and handed to the query as a value.
    scope :fresh, -> { where(seen_at: Presence::STALE_AFTER.ago..) }

    # The one row a tab has on a record.
    scope :of_tab, ->(user, record, tab) { where(user_id: user.id, record_type: record.class.polymorphic_name, record_id: record.id, tab:) }

    class << self
      # This tab is on the record, here, now. The same tab arriving again (a
      # reload that overlaps its old socket) is the same row: its state and
      # `seen_at` are refreshed and its `arrived_at` is kept.
      def arrive(user:, record:, tab:)
        now = Time.current
        upsert({ user_id: user.id, record_type: record.class.polymorphic_name, record_id: record.id, tab:, state: "here", seen_at: now, arrived_at: now }, # version: none (presence is not content)
          unique_by: :index_presence_marks_on_user_record_tab, update_only: %i[state seen_at])
        nil
      end

      # The tab's state changed. True when it did (a different, known state on
      # a row that is there); false for the same state, an unknown one and a
      # row that is not there. `seen_at` moves with a change only: that the
      # tab is still there is `beat`'s to say, and one statement cannot both
      # tell a change from none and touch an unchanged row.
      def report(user:, record:, tab:, state:)
        return false unless STATES.include?(state)

        of_tab(user, record, tab).where.not(state:).update_all(state:, seen_at: Time.current).positive? # version: none (presence is not content)
      end

      # The tab is still there. False when it has no row (it was swept, or it
      # never arrived).
      def beat(user:, record:, tab:)
        of_tab(user, record, tab).update_all(seen_at: Time.current).positive? # version: none (presence is not content)
      end

      # The tab went away.
      def leave(user:, record:, tab:)
        of_tab(user, record, tab).delete_all # version: none (presence is not content)
        nil
      end
    end
  end
end
