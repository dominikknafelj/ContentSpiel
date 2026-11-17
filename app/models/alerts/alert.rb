module Alerts
  # One alert: an error report or a security finding, folded by `fingerprint`
  # into one row that counts its occurrences.
  #
  # A job alone writes it (the error subscriber's job and the check job), as
  # mail's state columns are a job's: no audit event is written for an alert,
  # since an alert is derived from the audit log or from an error, and auditing
  # it would add a row per row. `details` holds the fixed keys of its kind and
  # nothing else: never an exception message, a request parameter, an address
  # or a typed email.
  class Alert < ApplicationRecord
    self.table_name = "alerts"

    KINDS = %w[error sign_in_failures owner_changed token_issued access_denied_burst request_limited].freeze
    SECURITY_KINDS = (KINDS - %w[error]).freeze

    # The span a security finding is counted over.
    WINDOW = 15.minutes
    # An alert seen again after its mail waits this long before it is mailed again.
    REMIND_AFTER = 1.hour
    # The least time between two digests.
    DIGEST_EVERY = 10.minutes
    # Rows older than this (by `last_seen_at`) are deleted.
    RETENTION = 30.days
    # System status shows the newest RECENT_LIMIT of the last RECENT.
    RECENT = 7.days
    RECENT_LIMIT = 10

    # What the drawing side translates, chosen here once for every surface
    # (System status, the digest mail), each with its own keys: `key` names
    # the wording (the kind, or its variant: `error_nowhere`, `owner_made_by`,
    # `token_issued`), `values` are the interpolations, picked from `details`,
    # with the window's `minutes` and the `count` a plural wording takes. No
    # words here.
    Sentence = Data.define(:key, :values)

    VALUE_KEYS = {
      "error" => %w[error_class place],
      "sign_in_failures" => %w[failed locked],
      "owner_changed" => %w[subject_label actor_name now_owner],
      "token_issued" => %w[token_name group_name actor_name],
      "access_denied_burst" => %w[denied actors],
      "request_limited" => %w[limited limits]
    }.freeze
    # The kinds counted over WINDOW, whose sentences say its minutes.
    WINDOW_KINDS = %w[sign_in_failures access_denied_burst request_limited].freeze
    # The value a kind's plural wording counts by.
    COUNTED_BY = { "access_denied_burst" => :actors, "request_limited" => :limited }.freeze
    # The audit log's actions a window kind is counted from (`Alerts::Rules`),
    # and what its "Show in audit log" link narrows to.
    WINDOW_ACTIONS = {
      "sign_in_failures" => %w[session.failed session.second_factor_failed session.confirmation_failed].freeze,
      "access_denied_burst" => %w[access.denied].freeze,
      "request_limited" => %w[request.limited].freeze
    }.freeze

    validates :kind, inclusion: { in: KINDS }

    # The last RECENT's alerts, newest seen first, at most RECENT_LIMIT: what System status lists.
    scope :recent, ->(now = Time.current) {
      where(last_seen_at: (now - RECENT)..).order(last_seen_at: :desc).limit(RECENT_LIMIT)
    }

    # Alerts last seen more than RETENTION ago: what the check job deletes.
    scope :expired, ->(now = Time.current) { where(last_seen_at: ...(now - RETENTION)) }

    # Alerts owed a mail: never mailed, or seen since the last mail and that
    # mail at least REMIND_AFTER old.
    scope :due, ->(now = Time.current) {
      table = arel_table
      never = table[:mailed_at].eq(nil)
      again = table[:last_seen_at].gt(table[:mailed_at]).and(table[:mailed_at].lteq(now - REMIND_AFTER))
      where(never.or(again))
    }

    # The fingerprint of an error alert: one row per class and place, whatever
    # the message said (`place` nil when no frame was the application's).
    def self.fingerprint_for_error(error_class, place) = Digest::SHA256.hexdigest("error|#{error_class}|#{place}")

    # When the last digest went out, nil if none did.
    def self.last_mailed_at = maximum(:mailed_at)

    def security? = SECURITY_KINDS.include?(kind)

    # THE AUDIT LOG'S FILTER FOR THIS ALERT'S EVENTS, as the params
    # `Audit::Filter` reads (the StudioAlerts card: "Show in audit log →"
    # opens the log narrowed to the alert, never the whole log): an owner
    # change's or a token's one event, a window kind's actions in the window
    # it was counted over (`after` inclusive, `before` exclusive, the span
    # `Alerts::Rules` counts). Nil for an error, which the log does not hold,
    # and for a row that names neither (nothing to narrow to). Data: the
    # route is the component's.
    def audit_filter
      return { event_id: details["audit_event_id"] } if details["audit_event_id"]

      start = window_start or return
      { actions: WINDOW_ACTIONS.fetch(kind), after: start.utc.iso8601, before: (start + WINDOW).utc.iso8601 }
    end

    def sentence
      values = VALUE_KEYS.fetch(kind).index_with { |key| details[key] }.symbolize_keys
      values[:limits] = Array(values[:limits]).join(", ") if kind == "request_limited"
      values[:minutes] = WINDOW.in_minutes.to_i if WINDOW_KINDS.include?(kind)
      count = values[COUNTED_BY[kind]] if COUNTED_BY.key?(kind)
      values[:count] = count if count
      Sentence.new(key: sentence_key(values), values: values)
    end

    private

    def window_start
      return unless WINDOW_ACTIONS.key?(kind) && details["window_start"].is_a?(String)

      Time.iso8601(details["window_start"])
    rescue ArgumentError
      nil
    end

    def sentence_key(values)
      case kind
      when "error" then values[:place] ? "error" : "error_nowhere"
      when "owner_changed" then "owner_#{values[:now_owner] ? "made" : "removed"}#{"_by" if values[:actor_name]}"
      when "token_issued" then values[:actor_name] ? "token_issued_by" : "token_issued"
      else kind
      end
    end
  end
end
