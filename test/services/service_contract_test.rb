require "test_helper"

# Access-control design spec §7 "Service table test": every write goes
# through an `ApplicationService`, so a service that forgets to authorize
# or to record an event is a hole in both the permissions and the audit
# log. This walks every subclass and reads the source of its class body:
# each must call `authorize!(` and `record_event(`, or say why not.
#
# A TRIPWIRE, not the contract. A source check is satisfied by a service that
# calls `authorize!(` and ignores the answer; whether a service really
# refuses, audits and changes nothing is proven by behaviour in
# `service_behaviour_contract_test.rb`. This one catches the new service that
# never thought about either, with an exemption for each check on its own:
#
#   # authorize: none (reason)   skips only the authorisation check
#   # audit: none (reason)       skips only the audit check
#
# Each is matched inside the class's own body (not the file, so a second
# service in the same file is not exempted by the first, and not a doc
# comment above `class`), and each names its reason. The reason is a claim a
# reviewer can check: `Posts::Bulk` and `Posts::BulkRestore` write nothing
# themselves (the single-record services they run authorize and audit), and
# `Users::UpdateProfile`'s only rule is that the actor is the user itself.
class ServiceContractTest < ActiveSupport::TestCase
  AUTHORIZE_EXEMPTION = /^\s*# authorize: none \(.+\)/
  AUDIT_EXEMPTION = /^\s*# audit: none \(.+\)/

  setup { Rails.application.eager_load! }

  # The lines of `class <leaf> ...` through its closing `end`, from a file's
  # source: the class body an exemption must sit in. Nil when the file has no
  # such class.
  def self.class_body(source, name)
    lines = source.lines
    start = lines.index { |line| line.match?(/^\s*class #{Regexp.escape(name.split("::").last)}\b/) }
    return unless start

    indent = lines[start][/\A\s*/]
    finish = (start + 1...lines.size).find { |index| lines[index].chomp == "#{indent}end" }
    lines[start..finish].join
  end

  test "there are services to check" do
    assert_operator services.size, :>=, 46
  end

  test "every service authorizes and records an event" do
    services.each do |service|
      body = body_of(service)
      code = body.lines.reject { |line| line.lstrip.start_with?("#") }.join # a comment mentioning `authorize!(` proves nothing

      assert_includes code, "authorize!(", "#{service} never calls authorize! (or say `# authorize: none (reason)` in its class body)" unless body.match?(AUTHORIZE_EXEMPTION)
      assert_includes code, "record_event(", "#{service} never calls record_event (or say `# audit: none (reason)` in its class body)" unless body.match?(AUDIT_EXEMPTION)
    end
  end

  test "an exemption is only valid inside the class it is written for" do
    source = <<~RUBY
      module Sample
        # audit: none (documented above the class, not in it)
        class First < ApplicationService
          def call = authorize!(:a, nil)
        end

        class Second < ApplicationService
          # authorize: none (the second one's own reason)
          def call = record_event("x")
        end
      end
    RUBY

    first = self.class.class_body(source, "Sample::First")
    second = self.class.class_body(source, "Sample::Second")
    assert_not_includes first, "second one's own reason"
    assert_no_match AUDIT_EXEMPTION, first
    assert_no_match AUTHORIZE_EXEMPTION, first
    assert_match AUTHORIZE_EXEMPTION, second
    assert_no_match AUDIT_EXEMPTION, second
  end

  private

  # The app's own services -- not the throwaway subclasses tests define
  # (`ApplicationServiceTest::NoOpService`), found by where the constant is
  # defined so a service outside app/services, or several to a file, count.
  def services
    root = Rails.root.join("app").to_s
    ApplicationService.descendants.select { |service| service.name && Object.const_source_location(service.name)&.first&.start_with?(root) }
  end

  def body_of(service)
    file, = Object.const_source_location(service.name)
    self.class.class_body(File.read(file), service.name) || flunk("#{service}'s class is not in #{file}")
  end
end
