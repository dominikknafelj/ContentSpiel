# Base for the write path (spec §7). Admin, MCP, setup and seeds perform the
# same actions through these, so roles, the audit log and versioning get one
# place each to attach -- which is why ContentSpiel goes beyond plain "fat
# models" here. Validation and rule failures come back as a Result, never an
# exception, so every caller branches the same way; anything unexpected
# propagates.
class ApplicationService
  Result = Data.define(:record, :errors) do
    def self.success(record) = new(record:, errors: [])
    def self.failure(record, errors) = new(record:, errors: Array(errors))

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
