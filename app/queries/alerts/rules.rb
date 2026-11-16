module Alerts
  # Reads the audit log for what an owner should be told, and writes it as
  # alerts (`Alerts::CheckJob` runs it). Reads chosen columns of
  # `audit_events` and never `snapshot`, nor `field_changes` beyond
  # `user.owner_changed`'s `owner`; nothing it writes holds an address, a typed
  # email or a request's words (a failed sign-in's metadata is never read).
  #
  # A window is `Alerts::Alert::WINDOW` long, aligned to the clock, and the
  # current and the previous are evaluated, so a window's end is never missed
  # by a scan that runs late. A window alert's fingerprint carries the window's
  # start, so there is one per window and a second scan updates it. A per-event
  # alert (an owner change, a token made) is `audit|<event id>`: inserted once,
  # a repeat ignored, for as long as the event is within two windows.
  class Rules
    FAILED_SIGN_INS = 20
    DENIED = 20
    LIMITED = 1

    FAILED_ACTIONS = %w[session.failed session.second_factor_failed session.confirmation_failed].freeze

    def initialize(now: Time.current)
      @now = now
    end

    # Alerts written or updated.
    def apply
      window = Alerts::Alert::WINDOW.to_i
      current = Time.at((@now.to_i / window) * window).utc
      starts = [ current - Alerts::Alert::WINDOW, current ]
      count = starts.sum { |start| sign_in_failures(start) + access_denied_burst(start) + request_limited(start) }
      count + per_event(starts.first)
    end

    private

    def span(start) = start...(start + Alerts::Alert::WINDOW)

    def events(actions, start) = Audit::Event.of_actions(actions).last_occurred_between(span(start))

    def sign_in_failures(start)
      failed_events = events(FAILED_ACTIONS, start)
      failed = failed_events.sum(:occurrences)
      return 0 if failed < FAILED_SIGN_INS

      locked = events("session.locked", start).sum(:occurrences)
      upsert_window("sign_in_failures", start, failed_events, failed, "failed" => failed, "locked" => locked)
    end

    def access_denied_burst(start)
      denied_events = events("access.denied", start)
      denied = denied_events.sum(:occurrences)
      return 0 if denied < DENIED

      actors = denied_events.distinct.count(:user_id) + (denied_events.exists?(user_id: nil) ? 1 : 0)
      upsert_window("access_denied_burst", start, denied_events, denied, "denied" => denied, "actors" => actors)
    end

    def request_limited(start)
      limited_events = events("request.limited", start)
      limited = limited_events.count
      return 0 if limited < LIMITED

      limits = limited_events.pluck(:metadata).filter_map { |metadata| metadata["limit"] if metadata.is_a?(Hash) }.uniq.sort
      upsert_window("request_limited", start, limited_events, limited, "limited" => limited, "limits" => limits)
    end

    # One row per kind and window; `first_seen_at` and `mailed_at` stay as
    # they were, the rest follows the window's events as they are now.
    def upsert_window(kind, start, window_events, occurrences, counts)
      Alerts::Alert.upsert( # version: none (alerts are no part of a page)
        { kind:, fingerprint: "#{kind}|#{start.iso8601}", occurrences:,
          details: { "window_start" => start.iso8601 }.merge(counts),
          first_seen_at: window_events.minimum(:occurred_at), last_seen_at: window_events.maximum(:last_occurred_at) },
        unique_by: :fingerprint, update_only: %i[occurrences details last_seen_at]
      )
      1
    end

    # Owner changes and tokens made in the last two windows, one alert each.
    def per_event(since)
      events = per_event_events(since).to_a
      return 0 if events.empty?

      people = User.where(id: events.flat_map { |event| [ event.user_id, (event.subject_id if event.subject_type == "User") ] }.compact).index_by(&:id)
      rows = events.map { |event| event_alert(event, people) }
      Alerts::Alert.insert_all(rows, unique_by: :fingerprint).length # version: none (alerts are no part of a page)
    end

    # The columns the per-event rules read, and not `snapshot`.
    def per_event_events(since)
      Audit::Event.of_actions(%w[user.owner_changed token.issued]).last_occurred_between(since..@now)
        .select(:id, :action, :user_id, :subject_type, :subject_id, :subject_label, :metadata, :field_changes, :occurred_at, :last_occurred_at)
        .order(:id)
    end

    # A subject that is a person is named as an actor is; any other label
    # loses what follows an at sign, since the log's label for a nameless
    # user is the whole address.
    def subject_name(event, people)
      person = people[event.subject_id] if event.subject_type == "User"
      return PersonName.of(person) if person

      event.subject_label&.split("@")&.first
    end

    # The actor as a note names a person: the name, else the part of the
    # address before the at sign, never the whole address; nil for the system.
    def event_alert(event, people)
      base = { "audit_event_id" => event.id, "actor_name" => (PersonName.of(people[event.user_id]) if people[event.user_id]) }
      details, kind =
        if event.action == "user.owner_changed"
          [ base.merge("subject_label" => subject_name(event, people), "now_owner" => Array(event.field_changes["owner"]).last == true), "owner_changed" ]
        else
          metadata = event.metadata.is_a?(Hash) ? event.metadata : {}
          [ base.merge("token_name" => metadata["name"], "group_name" => metadata["group"]), "token_issued" ]
        end
      { kind:, fingerprint: "audit|#{event.id}", details:, occurrences: 1,
        first_seen_at: event.occurred_at, last_seen_at: event.last_occurred_at }
    end
  end
end
