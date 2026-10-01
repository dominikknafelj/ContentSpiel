# The dashboard's "newest audit event per record" (`Dashboard::Feed`'s
# LATERAL join and its DISTINCT ON batch) orders each record's events by
# `last_occurred_at DESC` -- the coalescing column, not `occurred_at`, which
# is all the existing `(subject_type, subject_id, occurred_at)` index
# covers. This one lets each lookup read the newest row straight off the
# index instead of sorting a record's whole history.
class AddNewestEventIndexToAuditEvents < ActiveRecord::Migration[8.1]
  def change
    add_index :audit_events, [ :subject_type, :subject_id, :last_occurred_at ],
      order: { last_occurred_at: :desc }, name: "index_audit_events_on_subject_and_newest"
  end
end
