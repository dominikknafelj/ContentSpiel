module Users
  # When each of these users last signed in (round 3 Task 12, decision D19):
  # `{ user_id => Time }`, a user who never has simply absent (the screens say
  # "Never").
  #
  # Nothing is stored on the user. A session row is deleted at sign-out and so
  # can't answer "last", and a token's use is no sign-in. The record that does
  # survive is the audit log: `Admin::SessionsController#create` writes one
  # `session.created` event per sign-in with the user as actor (so `user_id` is
  # set), and a `session.*` event is never coalesced (`Audit::Coalescer` merges
  # only `*.updated` and `access.denied`), so `occurred_at` IS the moment.
  #
  # ONE grouped query for however many users are listed -- `MAX(occurred_at)
  # ... GROUP BY user_id` -- never one per row. `index_audit_events_on_user_id_
  # and_occurred_at` leads with `user_id`, so the planner finds each listed
  # user's events by index and filters the action on them; the cost is the
  # number of audit events those users have caused, not the size of the log
  # (every change they make is an event with their `user_id`, so it grows with
  # use, not with the number of users). No index was added: `(user_id, action,
  # occurred_at)` would make it a pure index probe, and is the first thing to
  # add if a site's audit log ever makes this list slow. The log is
  # append-only (a trigger refuses updates and deletes), so this can only ever
  # grow and an event can never be edited to rewrite a "last sign-in".
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
