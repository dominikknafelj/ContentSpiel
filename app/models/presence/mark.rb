module Presence
  # One person's browser tab on one record: `state` ("here", or "away" when
  # the tab is hidden or idle), `seen_at` (the last time the tab said it was
  # still there), `arrived_at` (when this tab first came, kept when the same
  # tab subscribes again), `state_at` (when `state` last changed or the row
  # was made: "away for 12 minutes" is counted from it, and a keep-alive never
  # moves it) and `token`, which says WHICH SUBSCRIPTION owns the row. The
  # unique index is user, record and tab.
  #
  # THE TOKEN. A tab keeps its id across a reconnect, so a new connection
  # arrives at the same row the old connection is still subscribed to, and the
  # server notices the old one is dead later, when it runs that connection's
  # `unsubscribed`. `arrive` therefore replaces the token with a fresh one and
  # `leave` deletes only a row that still carries ITS subscription's token: a
  # late leave of the older subscription finds another token and deletes
  # nothing.
  #
  # EVERY METHOD IS ONE STATEMENT and writes nothing but its own row: no
  # `touch`, nothing on the record, no audit event, no content version. There
  # are no callbacks, and the row is never saved through the model; `record`
  # is declared so that a query can say `where(record:)`, and it is optional
  # because the record's trashing or purging leaves its rows to go stale
  # (`fresh`, `Presence::Sweep`; a tab left open on it keeps its own fresh, and
  # every read is scoped).
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
      # A subscription of this tab is on the record, in `state` ("here" for a
      # new one), now. Answers the subscription's token. The same tab arriving
      # again (a reload that overlaps its old socket, a reconnect, or a beat
      # healing a lost row) is the same row: its token, state and `seen_at` are
      # replaced and its `arrived_at` is kept. `state_at` is reset by every
      # arrival, since an arrival says what the state is now.
      def arrive(user:, record:, tab:, token: SecureRandom.hex(8), state: "here")
        now = Time.current
        upsert({ user_id: user.id, record_type: record.class.polymorphic_name, record_id: record.id, tab:, token:, state:, seen_at: now, arrived_at: now, state_at: now }, # version: none (presence is not content)
          unique_by: :index_presence_marks_on_user_record_tab, update_only: %i[token state seen_at state_at])
        token
      end

      # The tab reports its state. ALWAYS moves `seen_at`; `state_at` moves
      # only when the state differs from the row's, said in the statement
      # (a CASE) and not decided in Ruby. True when the row is there; the
      # CHANNEL knows whether the state changed, from the one it remembers.
      # An unknown state writes nothing.
      def report(user:, record:, tab:, state:)
        return false unless STATES.include?(state)

        now = Time.current
        state_at = Arel::Nodes::Case.new.when(arel_table[:state].not_eq(state)).then(Arel::Nodes.build_quoted(now)).else(arel_table[:state_at])
        of_tab(user, record, tab).update_all(state:, seen_at: now, state_at:).positive? # version: none (presence is not content)
      end

      # The tab is still there. False when it has no row (it was swept, or
      # deleted by a late leave): the channel then puts it back.
      def beat(user:, record:, tab:)
        of_tab(user, record, tab).update_all(seen_at: Time.current).positive? # version: none (presence is not content)
      end

      # The subscription went away. True when it deleted a row, false when the
      # row is another subscription's by now (or already gone).
      def leave(user:, record:, tab:, token:)
        of_tab(user, record, tab).where(token:).delete_all.positive? # version: none (presence is not content)
      end
    end
  end
end
