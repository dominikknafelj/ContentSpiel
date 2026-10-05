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
    # existing row -- must match the trigger's list. `occurrences` counts the
    # saves a coalesced row stands for. `actor_label` is deliberately NOT
    # here: it is written once at INSERT and frozen.
    COALESCING_COLUMNS = %w[field_changes snapshot last_occurred_at occurrences].freeze

    belongs_to :actor, polymorphic: true, optional: true
    belongs_to :user, optional: true
    belongs_to :subject, polymorphic: true, optional: true

    scope :for_subject, ->(record) { where(subject: record) }
    scope :by_user, ->(user) { where(user_id: user.id) }

    # The events on either side of `event` in the log's own order
    # (`last_occurred_at, id`, see `Audit::Filter.ordered`): a row comparison
    # on the very pair `index_audit_events_on_recent` is ordered by, so the
    # neighbour of an event is one indexed lookup. Neither scope orders.
    scope :older_in_log_than, ->(event) { where("(audit_events.last_occurred_at, audit_events.id) < (?, ?)", event.last_occurred_at, event.id) }
    scope :newer_in_log_than, ->(event) { where("(audit_events.last_occurred_at, audit_events.id) > (?, ?)", event.last_occurred_at, event.id) }

    # Of the events in the relation, only the newest of each subject (by when
    # it was recorded, `occurred_at`, then id) -- `DISTINCT ON`, so however
    # many subjects are asked about it is one query. It selects and orders:
    # put the conditions before it.
    scope :newest_per_subject, -> {
      select("DISTINCT ON (audit_events.subject_type, audit_events.subject_id) audit_events.*")
        .order(Arel.sql("audit_events.subject_type, audit_events.subject_id, audit_events.occurred_at DESC, audit_events.id DESC"))
    }

    before_update :only_coalescing_columns_changed
    before_destroy { throw :abort }

    # A polymorphic `actor_type`/`subject_type` column stores a class name,
    # and reading `actor`/`subject` back constantizes whatever string is on
    # the row -- fine for a type that still exists, but this table is
    # append-only (this class's own comment) and can never be rewritten to
    # follow a model that's later renamed. Media library Task 1 renamed
    # `MediaAsset` to `Media::Asset`; without this override, `event.subject`
    # on a row recorded before that (`subject_type: "MediaAsset"`) would
    # raise `NameError` loading a constant that no longer exists -- crashing
    # `Admin::AuditEventsController#index`'s `includes(:subject, :user)` the
    # moment one such row appears on a page. One entry per rename, added
    # here as they happen; `Admin::AuditEventsController::SUBJECT_TYPES`
    # carries the equivalent for the filter whitelist and index/show
    # <select>, since that's a distinct, UI-only concern this append-only
    # model shouldn't otherwise depend on.
    LEGACY_POLYMORPHIC_TYPES = { "MediaAsset" => "Media::Asset" }.freeze

    def self.polymorphic_class_for(name)
      super(LEGACY_POLYMORPHIC_TYPES.fetch(name, name))
    end

    # "via <token name>" for an event an API token made: the name written
    # when the event was recorded, so it outlives the token. An event from
    # before names existed (token actor, no label) reads "an API token".
    # nil for anything that wasn't a token.
    def via_label
      return unless actor_type == "ApiToken"

      actor_label.presence || "an API token"
    end

    private

    def only_coalescing_columns_changed
      frozen = changed - COALESCING_COLUMNS
      return if frozen.empty?

      raise ActiveRecord::ReadOnlyRecord, "audit events are append-only (tried to change #{frozen.to_sentence})"
    end
  end
end
