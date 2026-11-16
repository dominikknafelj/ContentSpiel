module Alerts
  # Folds one error report into its alert (`Alerts::ErrorSubscriber`): a new
  # row for a class at a place not seen before, otherwise one more occurrence
  # on the row. One statement, so two reports of the same error at once both
  # count. A failure of this job is no alert (the subscriber drops a report
  # whose job is of this namespace), so a database that is down does not
  # chain reports.
  class RecordErrorJob < ApplicationJob
    queue_as :default

    def perform(error_class:, place:, source:, handled:, at:)
      Alert.upsert({ kind: "error", fingerprint: Alert.fingerprint_for_error(error_class, place), # version: none (alerts are no part of a page)
                     details: { error_class: error_class, place: place, source: source, handled: handled },
                     occurrences: 1, first_seen_at: at, last_seen_at: at },
        unique_by: :fingerprint,
        # sql: `upsert`'s ON CONFLICT ... DO UPDATE SET takes SQL text; Arel has no node for the `excluded` row
        on_duplicate: Arel.sql("occurrences = alerts.occurrences + 1, last_seen_at = GREATEST(alerts.last_seen_at, excluded.last_seen_at), updated_at = excluded.updated_at"))
      nil
    end
  end
end
