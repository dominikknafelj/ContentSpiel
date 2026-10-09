# Base for the write path (spec §7). Admin, MCP, setup and seeds perform the
# same actions through these, so roles, the audit log and versioning get one
# place each to attach -- which is why ContentSpiel goes beyond plain "fat
# models" here. Validation and rule failures come back as a Result, never an
# exception, so every caller branches the same way; anything unexpected
# propagates.
class ApplicationService
  # `denied` marks a failure that is a missing permission (`#denied`
  # below) rather than a validation or rule failure -- what lets a CS Studio
  # controller answer 403 for one and 422 for the other (access-control
  # design spec §3.4) without matching on the message text, which a
  # `message:` override (the owner-only user rules) changes anyway.
  Result = Data.define(:record, :errors, :denied) do
    def initialize(record:, errors:, denied: false) = super

    def self.success(record) = new(record:, errors: [])

    # `errors` defaults to `record.errors.full_messages` (see
    # `ApplicationService#failure` below), which is only non-empty when the
    # record's own validations actually ran and failed -- a service that
    # builds a failure some other way (a rule check with no matching
    # validation, a stubbed/mocked `save` in a test) can reach here with no
    # messages at all. Since `ok?` is just `errors.empty?`, that would read
    # as success, silently defeating the one thing a `Result` exists to
    # guarantee -- so an empty `errors` here always gets a generic fallback
    # message instead of being trusted as-is.
    def self.failure(record, errors = [])
      errors = Array(errors)
      errors = [ generic_failure_message(record) ] if errors.empty?
      new(record:, errors:)
    end

    def self.generic_failure_message(record)
      return "The change could not be saved" if record.nil?

      "#{record.class.model_name.human} could not be saved"
    end

    def ok? = errors.empty?

    def denied? = denied
  end

  def self.call(...) = new(...).call

  private

  # Who the service acts for (access-control design spec §3.3): the
  # `actor:` its constructor was given, which every service defaults to
  # `Current.actor`. A service that never stored one falls back to
  # `Current.actor` directly.
  def actor = defined?(@actor) ? @actor : Current.actor

  # The person behind `actor`: the user itself, or an API token's user
  # (what a new post's `author_id` is set to). Nil for a trusted code path.
  def actor_user = actor.is_a?(ApiToken) ? actor.user : actor

  # The one enforcement point (design spec §3.4): may `actor` do `key`
  # (`"posts.edit"`, `"tags.manage"`, ...) to `record`? A plain Boolean --
  # every service pairs it with `denied` below, as
  #
  #   return denied("posts.edit", @post) unless authorize!("posts.edit", @post)
  #
  # so the refusal is both logged and answered the same way everywhere.
  # A subject key (posts.*/pages.*) needs its record -- `AccessControl
  # .allowed?` raises on nil rather than allowing scope-free. The channel
  # is `Current.channel`: a nil actor is trusted on `:setup`/`:console`/
  # `:system`/nil and denied on `:admin`/`:mcp`.
  def authorize!(key, record) = AccessControl.allowed?(actor, key, record)

  # Records `access.denied` (design spec §4.3, the denied permission and
  # the subject in `metadata`) and answers with the permission failure
  # every caller shows as-is (Global Constraints' denial message).
  # `message:` overrides that text for a rule that isn't a missing
  # permission of its own (the owner-only rules on users).
  #
  # Call it *outside* the service's own transaction: a denial is the one
  # event that must survive the rollback of the write it refused (a
  # forged PATCH gets one coalesced `access.denied`, Review Focus 4). A
  # check that can only run after assigning attributes inside the
  # transaction rolls back first and calls this afterwards (see
  # `Posts::Save`).
  #
  # An unsaved record (a refused create) isn't stored as the subject:
  # `Audit::Event#subject` would otherwise have to point at a row that
  # doesn't exist. Its type goes into `metadata` instead.
  def denied(key, record, message: nil)
    permission = AccessControl::Permissions.fetch(key)
    subject = record.is_a?(ActiveRecord::Base) && record.persisted? ? record : nil
    metadata = { "permission" => permission.key }
    metadata["subject_type"] = record.class.polymorphic_name if record.is_a?(ActiveRecord::Base) && subject.nil?

    as_actor { Audit.record("access.denied", subject:, metadata:) }
    Result.new(record:, errors: [ message || "You don't have permission to #{permission.label.downcase}" ], denied: true)
  end

  # Writes to the audit log (access-control design spec §4.2) through
  # `Audit.record`, with the subject's snapshot taken here -- so every
  # service logs the full record the same way, and none can forget to.
  # `action` is an `area.verb` name from the spec's event catalogue (§4.3),
  # e.g. `"post.updated"`; `field_changes` is usually
  # `Audit::Snapshot.field_changes_for(record)`. Call it inside the
  # service's transaction, so a rolled-back write leaves no event.
  #
  # `snapshot: nil` leaves the snapshot out: for an event about a record
  # that didn't change (`ai.translated`, which must carry no text at all),
  # a full copy of the subject would only put its content in the log.
  #
  # `coalesce: false` is `Audit.record`'s: for an `*.updated` event that
  # carries `metadata`, which an event coalesced into an open row loses.
  def record_event(action, subject: nil, field_changes: {}, metadata: {}, snapshot: Audit::Snapshot.for(subject), coalesce: true)
    as_actor do
      Audit.record(action, subject:, field_changes:, snapshot:, metadata:, coalesce:)
    end
  end

  # `Audit.record` reads the actor from `Current` (so a caller can't forge
  # one), but a service may be handed an explicit `actor:` that differs --
  # `Users::UpdatePassword` from the reset flow, where nobody is signed in
  # and the reset token itself authenticated the user. The event is
  # attributed to the actor the service actually acted for.
  def as_actor(&block)
    return yield if actor.equal?(Current.actor)

    Current.set(actor: actor, &block)
  end

  def success(record) = Result.success(record)
  def failure(record, errors = record.errors.full_messages) = Result.failure(record, errors)
end
