require "test_helper"

# Access-control design spec §7 "Service table test": every write goes
# through an `ApplicationService`, so a service that forgets to authorize
# or to record an event is a hole in both the permissions and the audit
# log. This walks every subclass and reads its `#call` source: each must
# call `authorize!(` and `record_event(`, or say why not with an explicit
# `# audit: none (reason)` comment. That list is empty today -- keep it so.
#
# A source check, not a behavioural one (the matrix test and each
# service's own tests cover behaviour): it catches the new service that
# never thought about either, which is what it's for.
class ServiceContractTest < ActiveSupport::TestCase
  EXEMPTION = /# audit: none \(.+\)/

  setup { Rails.application.eager_load! }

  test "there are services to check" do
    assert_operator services.size, :>=, 20
  end

  test "every service authorizes and records an event in #call" do
    services.each do |service|
      source = call_source(service)
      next if source.match?(EXEMPTION)

      # Code only: a comment mentioning `authorize!(` proves nothing.
      source = source.lines.reject { |line| line.lstrip.start_with?("#") }.join

      assert_includes source, "authorize!(", "#{service}#call never calls authorize!"
      assert_includes source, "record_event(", "#{service}#call never calls record_event"
    end
  end

  private

  # The app's own services -- not the throwaway subclasses tests define
  # (`ApplicationServiceTest::NoOpService`).
  def services
    root = Rails.root.join("app/services").to_s
    ApplicationService.descendants.select { |service| service.instance_method(:call).source_location.first.start_with?(root) }
  end

  # The file `#call` is defined in, not just the method body: a service
  # may reach `record_event` from a private helper next to it (`Posts::
  # Save#record_events`), which is still its own `#call` at work. Shared
  # helpers in other files (`ContentBlocks::OwnerPermissions`) don't count
  # -- the service itself must say `authorize!(`.
  def call_source(service)
    file, = service.instance_method(:call).source_location
    File.read(file)
  end
end
