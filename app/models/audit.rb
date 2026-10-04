# The audit log (access-control design spec §4): who did what to which
# record, through which door, as an append-only table (`Audit::Event`).
#
# `Audit.record` is the single write path -- `ApplicationService#record_event`
# delegates to it, so every CS Studio, MCP, setup and console write that goes
# through a service is logged the same way. It reads the actor, channel,
# request id and IP from `Current` rather than taking them as arguments,
# so a service can't forget (or forge) them.
module Audit
  # Measured from the previous event's `last_occurred_at`, not its
  # `occurred_at` (spec §4.2) -- a continuous autosave session keeps
  # extending one event for as long as the gaps between saves stay under
  # ten minutes, however long the session runs overall.
  COALESCE_WINDOW = 10.minutes

  # The plugin hook (spec §4.2): published once per new or extended event,
  # only after the transaction it was written in commits, with payload
  # `{ event: }`.
  NOTIFICATION = "audit.content_spiel"

  # Writes (or, for a coalescible action, extends) an event inside the
  # caller's transaction, if there is one -- so a save that rolls back
  # leaves no trace in the log (spec §4.2). Returns the `Audit::Event`.
  #
  # `snapshot:` is usually `Audit::Snapshot.for(subject)` (which
  # `ApplicationService#record_event` passes); `subject_label` is derived
  # here, from the subject as it is right now, so the event still reads
  # well after the subject is renamed or deleted.
  #
  # A backstop for secrets (Review Focus 5): `field_changes` and a Hash
  # `snapshot` go through `Snapshot.scrub` here too, whoever built them --
  # a caller hand-assembling either can't leak a `password_digest` or a
  # `filter_parameters` match. `metadata` is left alone: it's written by
  # the recording code itself, and `session.failed` carries the tried
  # email in it by design.
  def self.record(action, subject: nil, field_changes: {}, snapshot: nil, metadata: {})
    action = action.to_s
    now = Time.current
    actor = Current.actor
    attributes = {
      action:,
      actor:,
      user_id: actor.is_a?(ApiToken) ? actor.user_id : actor&.id,
      # The acting token's name, kept on the row itself (round 3 decision
      # D1): the token can be deleted later (with its group or user) and the
      # event must still say "via <name>". Written once, at INSERT; a
      # coalesced merge never changes it (the Coalescer matches on actor, so
      # the open row already carries the same token's name).
      actor_label: actor.is_a?(ApiToken) ? actor.name : nil,
      channel: (Current.channel || default_channel).to_s,
      subject:,
      subject_label: Snapshot.label_for(subject),
      field_changes: Snapshot.scrub(field_changes.to_h.as_json),
      snapshot: snapshot.is_a?(Hash) ? Snapshot.scrub(snapshot.as_json) : snapshot&.as_json,
      metadata: metadata.to_h.as_json,
      request_id: Current.request_id,
      ip: Current.ip_address
    }

    event = Event.transaction do
      Coalescer.extend_existing(attributes, now:) || Event.create!(attributes.merge(occurred_at: now, last_occurred_at: now))
    end

    # Runs immediately when there's no enclosing transaction, otherwise
    # once every open one has committed -- never for a rolled-back one.
    ActiveRecord.after_all_transactions_commit { ActiveSupport::Notifications.instrument(NOTIFICATION, event:) }

    event
  end

  # `Current.channel` is only set inside a request (spec §7.1). Outside one,
  # an interactive console is the one case we can tell apart; everything
  # else -- rake tasks, jobs, seeds, tests -- is the system acting.
  def self.default_channel
    defined?(Rails::Console) ? :console : :system
  end
  private_class_method :default_channel
end
