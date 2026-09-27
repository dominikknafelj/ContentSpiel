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

  # Attachment point for the audit log (sub-project 5).
  def record_event(_name, **_data) = nil

  def success(record) = Result.success(record)
  def failure(record, errors = record.errors.full_messages) = Result.failure(record, errors)
end
