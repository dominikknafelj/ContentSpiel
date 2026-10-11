module Editing
  # One subject (a block, a page's settings, a post) held by one browser tab
  # of one person (live-editing spec §4). `changed_at` is the holder's last
  # saved change or claim; the row is LIVE until `changed_at + Editing::HOLD`
  # and counts as no row from that instant on, whatever the sweep has done:
  # a row exactly HOLD old is NOT live (`live` is `changed_at > now - HOLD`,
  # and `CLAIM` takes a row whose `changed_at <= now - HOLD`, the same
  # boundary from both sides, so at that instant exactly one reading holds).
  # `requested_*` is a pending take-over: who asked, from which tab, when.
  # It exists only while `requested_by_id` is set (the foreign key nullifies
  # it when that person is deleted): see `#requested?`.
  #
  # EVERY METHOD IS ONE STATEMENT on the unique index of the subject, so two
  # tabs can never both hold one; none takes a row lock, none runs a callback
  # and none writes anything but its own row: no `touch`, nothing of the
  # record, no audit event, no content version. The clock is the caller's
  # (`now:`), handed to the statement as a value (never the database's
  # NOW()), so a test asks about any instant without moving time.
  #
  # NOT A SERVICE (`CLAUDE.md`): a reservation is not content, nobody asks for
  # one by name and it is gone in two minutes; audited, it would flood the
  # log. The one audited write is `Editing::TakeOver`.
  class Reservation < ApplicationRecord
    self.table_name = "edit_reservations"

    belongs_to :user
    belongs_to :requested_by, class_name: "User", optional: true
    belongs_to :subject, polymorphic: true, optional: true
    belongs_to :record, polymorphic: true, optional: true

    # Live at `now`: changed less than HOLD ago.
    scope :live, ->(now = Time.current) { where(arel_table[:changed_at].gt(now - Editing::HOLD)) }
    scope :of, ->(subject) { where(subject_type: subject.class.polymorphic_name, subject_id: subject.id) }
    scope :on, ->(record) { where(record_type: record.class.polymorphic_name, record_id: record.id) }

    # Inserts the row, or takes an expired one, or renews the tab's own; a
    # live row of another tab is left as it is and the statement returns
    # nothing. `renewed` is read from the row as it stood when the statement
    # began (the CTE sees the statement's snapshot; a concurrent claim by the
    # SAME tab that wins the insert first is therefore reported as `taken` by
    # the other: the row is right, only the word differs). The WHERE of the
    # DO UPDATE is re-checked by Postgres against the newest version of the
    # row after waiting for a concurrent writer, which is what makes two
    # simultaneous claims of one expired row end with exactly one holder. A
    # pending request survives the holder's own renewal and goes with an
    # expired row (and with a request whose requester is gone).
    CLAIM = <<~SQL.squish.freeze # sql: INSERT ... ON CONFLICT DO UPDATE ... WHERE has no Arel node, and a claim must be one statement
      WITH before AS (
        SELECT user_id, tab, changed_at FROM edit_reservations WHERE subject_type = :subject_type AND subject_id = :subject_id
      )
      INSERT INTO edit_reservations (subject_type, subject_id, record_type, record_id, user_id, tab, changed_at)
      VALUES (:subject_type, :subject_id, :record_type, :record_id, :user_id, :tab, :now)
      ON CONFLICT (subject_type, subject_id) DO UPDATE
        SET record_type = EXCLUDED.record_type, record_id = EXCLUDED.record_id,
            user_id = EXCLUDED.user_id, tab = EXCLUDED.tab, changed_at = EXCLUDED.changed_at,
            requested_by_id = CASE WHEN edit_reservations.changed_at > :cutoff THEN edit_reservations.requested_by_id END,
            requested_tab = CASE WHEN edit_reservations.changed_at > :cutoff AND edit_reservations.requested_by_id IS NOT NULL THEN edit_reservations.requested_tab END,
            requested_at = CASE WHEN edit_reservations.changed_at > :cutoff AND edit_reservations.requested_by_id IS NOT NULL THEN edit_reservations.requested_at END
        WHERE edit_reservations.changed_at <= :cutoff
           OR (edit_reservations.user_id = EXCLUDED.user_id AND edit_reservations.tab = EXCLUDED.tab)
      RETURNING COALESCE((SELECT user_id = :user_id AND tab = :tab AND changed_at > :cutoff FROM before), FALSE) AS renewed
    SQL

    class << self
      def claim(subject:, record:, user:, tab:, now: Time.current)
        # sql: binds the named values of CLAIM, the one statement a claim is
        statement = sanitize_sql_array([ CLAIM, {
          subject_type: subject.class.polymorphic_name, subject_id: subject.id,
          record_type: record.class.polymorphic_name, record_id: record.id,
          user_id: user.id, tab:, now:, cutoff: now - Editing::HOLD
        } ])
        # sql: sends CLAIM, which has no Arel form
        rows = connection.exec_query(statement, "Editing claim") # version: none (a reservation is not content)
        return :refused if rows.empty?

        rows.first["renewed"] ? :renewed : :taken
      end

      def release(subject:, user:, tab:)
        of(subject).where(user_id: user.id, tab:).delete_all.positive? # version: none (a reservation is not content)
      end

      # Someone asks for a subject another tab holds. `requested_at` is kept
      # when the same tab asks again: the pass-over time runs from the first ask.
      def request(subject:, by:, tab:, now: Time.current)
        same = arel_table[:requested_by_id].eq(by.id).and(arel_table[:requested_tab].eq(tab))
        requested_at = Arel::Nodes::Case.new.when(same).then(arel_table[:requested_at]).else(Arel::Nodes.build_quoted(now))
        of(subject).live(now).where.not(user_id: by.id, tab:)
          .update_all(requested_by_id: by.id, requested_tab: tab, requested_at:).positive? # version: none (a reservation is not content)
      end

      # The holder's tab lets go: the row is the requester's from now.
      def hand_over(subject:, user:, tab:, now: Time.current)
        pass(of(subject).where(user_id: user.id, tab:).where.not(requested_by_id: nil), now)
      end

      # The holder's tab did not answer in PASS_OVER: the requester takes the row.
      def pass_over(subject:, by:, tab:, now: Time.current)
        pass(of(subject).where(requested_by_id: by.id, requested_tab: tab).where(arel_table[:requested_at].lteq(now - Editing::PASS_OVER)), now)
      end

      def holder_of(subject, now: Time.current) = of(subject).live(now).includes(:user).first

      private

      def pass(rows, now)
        rows.update_all(user_id: arel_table[:requested_by_id], tab: arel_table[:requested_tab], changed_at: now, # version: none (a reservation is not content)
          requested_by_id: nil, requested_tab: nil, requested_at: nil).positive?
      end
    end

    # A request is pending only while its requester exists.
    def requested? = requested_by_id.present?
  end
end
