require "test_helper"
require_relative "../support/service_calls"

# The service contract, proven by behaviour (technical cleanup spec §3.4).
# `service_contract_test.rb` greps each service's source for `authorize!(`
# and `record_event(`; that passes a service that calls `authorize!` and
# throws the answer away. This test never reads source: it runs every
# `ApplicationService` as an actor who may do nothing and observes the
# effects -- the answer, the audit rows and the data.
#
# For every service (a valid call built by `test/support/service_calls.rb`):
#
# - the answer is a refusal (`denied?`), not a validation failure or an
#   exception;
# - exactly one audit row is written, an `access.denied` with one occurrence,
#   attributed to the actor and channel the call ran on;
# - nothing else changed: the row counts of every table the service writes
#   and the attributes of the record (and of any second record) it acts on
#   are what they were before.
#
# The actor is a user with no memberships on the :admin channel, and, where
# MCP reaches the service, an API token of that user (in the Admin group, so
# only the intersection with the user's own rights can refuse it) on :mcp.
# The trusted nil actor is allowed by design and is never used here: every
# call sets an actor and a channel, so nothing passes by accident through
# that path.
#
# "Not found, not forbidden" is the controllers' and `AccessControl.scope`'s
# rule. A service handed the record directly has found it already, so it
# answers `denied`.
class ServiceBehaviourContractTest < ActiveSupport::TestCase
  include ServiceCalls::Builders

  Rails.application.eager_load!

  # The app's own services: classes defined under app/, not the throwaway
  # subclasses tests define (`ApplicationServiceTest::NoOpService`). Found by
  # where the constant is defined, so a service defined several to a file, or
  # outside app/services, is still found.
  def self.services
    root = Rails.root.join("app").to_s
    ApplicationService.descendants.select do |klass|
      klass.name && Object.const_source_location(klass.name)&.first&.start_with?(root)
    end.sort_by(&:name)
  end

  def nobody
    @nobody ||= User.create!(email_address: "nobody@example.com", password: ServiceCalls::PASSWORD)
  end

  def nobodys_token
    @nobodys_token ||= ApiToken.generate!(nobody, group: access_control_groups(:admin)).first
  end

  # What a refusal must leave untouched: row counts and the attributes of
  # every record named.
  def snapshot(tables, records)
    {
      counts: tables.index_with(&:count),
      attributes: records.compact.map { |record| [ record.class.name, record.id, record.class.unscoped.find_by(id: record.id)&.attributes ] }
    }
  end

  # Runs `call` as `actor` on `channel` and asserts the whole contract.
  def assert_refused_and_unchanged(label, call:, tables:, records:, actor:, channel:)
    audit_ids = Audit::Event.pluck(:id)
    before = snapshot(tables, records)

    result = Current.set(actor: actor, channel: channel) { call.call }

    assert_respond_to result, :denied?, "#{label} did not answer with an ApplicationService::Result"
    assert_predicate result, :denied?, "#{label} was not refused (errors: #{result.errors.inspect})"
    assert_not_predicate result, :ok?, "#{label} answered ok for an actor with no grants"

    events = Audit::Event.where.not(id: audit_ids).to_a
    assert_equal [ "access.denied" ], events.map(&:action), "#{label} must write exactly one audit event, an access.denied"
    assert_equal 1, events.first.occurrences, "#{label} recorded the denial more than once"
    assert_equal channel.to_s, events.first.channel
    assert_equal nobody.id, events.first.user_id, "#{label}'s denial is not attributed to the actor"

    after = snapshot(tables, records)
    assert_equal before[:counts], after[:counts], "#{label} changed the row count of a table although it refused"
    assert_equal before[:attributes], after[:attributes], "#{label} changed a record although it refused"
  end

  services.each do |klass|
    # A service with no factory and no exemption fails here, naming what to do.
    unless ServiceCalls::FACTORIES.key?(klass.name) || ServiceCalls.exempt?(klass)
      test "#{klass} has a call factory" do
        flunk "add a call factory for #{klass} to test/support/service_calls.rb"
      end
      next
    end
    next if ServiceCalls::ABSTRACT.include?(klass.name)

    if ServiceCalls::OWN_RESULT.key?(klass.name)
      test "#{klass} reports every id as not found to an actor who can read nothing" do
        built = ServiceCalls.for(klass, self)
        before_audit = Audit::Event.count
        before = snapshot(built[:tables], [ built[:subject], *built[:also] ])

        result = Current.set(actor: nobody, channel: :admin) { built[:call].call }

        assert_equal built[:ids].size, result.not_found
        %i[done restored refused failed].each { |list| assert_empty result.public_send(list), "#{klass}##{list}" if result.respond_to?(list) }
        assert_empty result.reasons
        # Not found, never forbidden: no denial is recorded either. Each post
        # that WOULD have been acted on is authorized and audited by the
        # single-record service the bulk one runs.
        assert_equal before_audit, Audit::Event.count, "#{klass} wrote an audit event for ids it could not read"
        assert_equal before, snapshot(built[:tables], [ built[:subject], *built[:also] ])
      end
      next
    end

    variants = [ nil ] + ServiceCalls.variants(klass)
    variants.each do |variant|
      label = variant ? "#{klass} (#{variant})" : klass.name

      # A SELF_SERVICE class is refused for a stranger like any other; its
      # own-record rule is tested below.
      test "#{label} refuses an actor with no grants" do
        built = ServiceCalls.for(klass, self, variant: variant)
        assert_refused_and_unchanged(label, call: built[:call], tables: built[:tables], records: [ built[:subject], *built[:also] ],
          actor: nobody, channel: :admin)
      end

      next unless ServiceCalls::MCP_REACHABLE.key?(klass.name)

      test "#{label} refuses a token of a user with no grants" do
        built = ServiceCalls.for(klass, self, variant: variant)
        assert_refused_and_unchanged("#{label} by token", call: built[:call], tables: built[:tables],
          records: [ built[:subject], *built[:also] ], actor: nobodys_token, channel: :mcp)
      end
    end

    next unless ServiceCalls::SELF_SERVICE.key?(klass.name)

    test "#{klass} lets a user act on their own record, and audits it" do
      built = ServiceCalls.for(klass, self)
      audit_ids = Audit::Event.pluck(:id)

      result = Current.set(actor: built[:owner], channel: :admin) { built[:own].call }

      assert_predicate result, :ok?, "#{klass} refused a user acting on their own record: #{result.errors.inspect}"
      events = Audit::Event.where.not(id: audit_ids).to_a
      assert_includes events.map(&:action), built[:own_event]
      assert_not_includes events.map(&:action), "access.denied"
      assert(events.all? { |event| event.user_id == built[:owner].id }, "#{klass}'s event is not attributed to the owner")
    end

    # Own record, but as a token: a token acts within its group and its
    # user's rights, and has no business with the account itself.
    test "#{klass} refuses a token of the record's own user who has no grants" do
      built = ServiceCalls.for(klass, self)
      owner = built[:owner]
      token = ApiToken.generate!(owner, group: access_control_groups(:admin)).first
      audit_ids = Audit::Event.pluck(:id)
      records = [ built[:own_subject] || owner, built[:subject] ]
      before = snapshot(built[:tables], records)

      result = Current.set(actor: token, channel: :mcp) { built[:own].call }

      assert_predicate result, :denied?, "#{klass} let a token act on its user's own record (errors: #{result.errors.inspect})"
      assert_equal [ "access.denied" ], Audit::Event.where.not(id: audit_ids).pluck(:action)
      assert_equal before[:attributes], snapshot(built[:tables], records)[:attributes]
    end
  end

  test "there are services to check" do
    assert_operator self.class.services.size, :>=, 33
  end

  test "every exemption names a real service" do
    names = self.class.services.map(&:name)
    (ServiceCalls::SELF_SERVICE.keys + ServiceCalls::OWN_RESULT.keys + ServiceCalls::FACTORIES.keys + ServiceCalls::MCP_REACHABLE.keys +
      ServiceCalls::VARIANTS.keys).each do |name|
      assert_includes names, name, "#{name} in test/support/service_calls.rb is not an ApplicationService"
    end
  end
end
