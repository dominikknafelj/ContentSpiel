module Audit
  # One row of the audit log (access-control design spec §4.1). Written only
  # by `Audit.record`.
  #
  # Append-only, twice over: this model refuses destroys and any update
  # outside the coalescing columns, and the `audit_events_append_only`
  # database trigger (db/triggers/audit_events_append_only.sql) refuses the
  # same at the SQL level, which also covers `delete_all`/`update_all` and
  # raw SQL that never reach these callbacks.
  #
  # No foreign keys, and every association optional: an event outlives its
  # actor and subject (a deleted post, user or token) -- `subject_label`
  # keeps it readable, and `subject`/`actor` simply read back nil.
  class Event < ApplicationRecord
    self.table_name = "audit_events"

    # The only columns coalescing (`Audit::Coalescer`) may change on an
    # existing row -- must match the trigger's list.
    COALESCING_COLUMNS = %w[field_changes snapshot last_occurred_at].freeze

    belongs_to :actor, polymorphic: true, optional: true
    belongs_to :user, optional: true
    belongs_to :subject, polymorphic: true, optional: true

    scope :for_subject, ->(record) { where(subject: record) }
    scope :by_user, ->(user) { where(user_id: user.id) }
    scope :recent, -> { order(occurred_at: :desc, id: :desc) }

    before_update :only_coalescing_columns_changed
    before_destroy { throw :abort }

    private

    def only_coalescing_columns_changed
      frozen = changed - COALESCING_COLUMNS
      return if frozen.empty?

      raise ActiveRecord::ReadOnlyRecord, "audit events are append-only (tried to change #{frozen.to_sentence})"
    end
  end
end
