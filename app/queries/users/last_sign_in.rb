module Users
  # When each of these users last signed in (round 3 Task 12, decision D19):
  # `{ user_id => Time }`, a user who never has simply absent (the screens say
  # "Never").
  #
  # Nothing is stored on the user. A session row is deleted at sign-out and so
  # can't answer "last", and a token's use is no sign-in. The record that does
  # survive is the audit log: `Admin::SessionsController#create` -- and the
  # setup wizard, for the founding owner it signs in (`SetupController#update_
  # admin`) -- writes one `session.created` event per sign-in with the user as
  # actor (so `user_id` is set), and a `session.*` event is never coalesced
  # (`Audit::Coalescer` merges only `*.updated` and `access.denied`), so
  # `occurred_at` IS the moment.
  #
  # ONE grouped query for however many users are listed -- `MAX(occurred_at)
  # ... GROUP BY user_id` -- never one per row. What it costs is NOT a pure
  # index probe: no index covers `(user_id, action)`. The planner has two to
  # choose from -- `index_audit_events_on_user_id_and_occurred_at` (every
  # event the listed users caused, the action filtered afterwards) and
  # `index_audit_events_on_action_and_occurred_at` (every sign-in on record,
  # the users filtered afterwards) -- and reads whichever it estimates
  # smaller; either way the work grows with the audit log, not just with the
  # number of users listed. The Users list is not paginated, so that is one
  # such query for all users. Fine for the log sizes this app has; `(user_id,
  # action, occurred_at)` is the index to add if this list ever gets slow.
  # The log is append-only (a trigger refuses updates and deletes), so an
  # event can never be edited to rewrite a "last sign-in".
  #
  # Only the sign-in a user made themselves counts: an event naming someone as
  # its SUBJECT but caused by another user (none of `session.created`) isn't
  # read, since the filter is on the event's own `user_id`.
  module LastSignIn
    ACTION = "session.created".freeze

    module_function

    def for(users)
      ids = Array(users).map { |user| user.respond_to?(:id) ? user.id : user }.compact
      return {} if ids.empty?

      Audit::Event.where(action: ACTION, user_id: ids).group(:user_id).maximum(:occurred_at)
    end
  end
end
