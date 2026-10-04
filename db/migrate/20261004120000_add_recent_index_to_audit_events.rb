# The dashboard's "Recent activity" sorts the whole (append-only, ever-growing)
# audit table by `last_occurred_at DESC, id DESC LIMIT n`; without this index
# that is a sort of every row on the landing page. Adding an index doesn't
# touch the append-only trigger (it guards UPDATE/DELETE, not DDL).
class AddRecentIndexToAuditEvents < ActiveRecord::Migration[8.1]
  def change
    add_index :audit_events, [ :last_occurred_at, :id ], order: { last_occurred_at: :desc, id: :desc },
      name: "index_audit_events_on_recent"
  end
end
