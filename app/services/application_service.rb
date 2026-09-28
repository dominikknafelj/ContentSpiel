# Base for the write path (spec §7). Admin, MCP, setup and seeds perform the
# same actions through these, so roles, the audit log and versioning get one
# place each to attach -- which is why ContentSpiel goes beyond plain "fat
# models" here. Validation and rule failures come back as a Result, never an
# exception, so every caller branches the same way; anything unexpected
# propagates.
class ApplicationService
  Result = Data.define(:record, :errors) do
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
  end

  def self.call(...) = new(...).call

  private

  # Attachment point for policies (sub-project 5). Deliberately permissive.
  def authorize!(_action, _record) = true

  # Writes to the audit log (access-control design spec §4.2) through
  # `Audit.record`, with the subject's snapshot taken here -- so every
  # service logs the full record the same way, and none can forget to.
  # `action` is an `area.verb` name from the spec's event catalogue (§4.3),
  # e.g. `"post.updated"`; `field_changes` is usually
  # `Audit::Snapshot.field_changes_for(record)`. Call it inside the
  # service's transaction, so a rolled-back write leaves no event.
  #
  # `**legacy` and the dot check are a temporary shim until Task 6 rewires
  # the services: today's call sites still use the placeholder form
  # `record_event(:post_saved, post: @post)`, from after their transaction
  # commits. Those are ignored rather than logged half-right (a snake_case
  # name no catalogue lists, no subject); Task 6 replaces every one and
  # removes this shim.
  def record_event(action, subject: nil, field_changes: {}, metadata: {}, **legacy)
    return nil unless legacy.empty? && action.to_s.include?(".")

    Audit.record(action, subject:, field_changes:, snapshot: Audit::Snapshot.for(subject), metadata:)
  end

  def success(record) = Result.success(record)
  def failure(record, errors = record.errors.full_messages) = Result.failure(record, errors)
end
