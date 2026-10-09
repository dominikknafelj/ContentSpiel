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
# SCOPE. This contract proves the FIRST refusal for an actor with no grants:
# the right key, on the right record, and nothing written. The branches of a
# service's rule (publish-only saves, edits to a live record, other subject
# types, the uploader rule, scoped grants, `languages.manage`, escalation of
# groups and users) belong to `authorization_matrix_test.rb`, which owns them.
#
# Nothing is read from source and no list of tables is trusted: the data is
# a digest of every table but the audit log, before and after. A CONTROL
# run (the same call, allowed, in a rolled-back savepoint) must answer ok and
# change something, so "changes nothing" cannot be true of a call that would
# have changed nothing anyway.
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

  # Every service, by name. Adding or deleting one is a deliberate edit here
  # (and a factory in test/support/service_calls.rb).
  EXPECTED_SERVICES = %w[
    AI::Translate ApiTokens::Issue ApiTokens::Revoke ContentBlocks::Destroy ContentBlocks::Duplicate ContentBlocks::Reorder
    ContentBlocks::Save Groups::Destroy Groups::Save Locales::Configure Locales::Disable Locales::Enable Locales::MakeDefault Media::Save
    Media::Upload Notes::DeleteMessage Notes::EditMessage Notes::MarkRead Notes::Pin Notes::Remove Notes::Reopen Notes::Reply Notes::Resolve
    Notes::SetFollowing Notes::Start Notes::Unpin Pages::Move Pages::Save Posts::Bulk Posts::BulkRestore Posts::Save Settings::Save
    StarterContents::Add StarterContents::EnsureHome Tags::Destroy Tags::Merge Tags::Rename Translations::Confirm
    Trash::Empty Trash::Move Trash::Purge Trash::Restore Users::Destroy Users::Save Users::UpdateNotifications
    Users::UpdatePassword Users::UpdateProfile
  ].freeze

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

  # A provider registered for `AI::Translate`'s factory is reset afterwards.
  teardown { Rails.application.reloader.prepare! if @ai_providers_registered }

  def nobody
    @nobody ||= User.create!(email_address: "nobody@example.com", password: ServiceCalls::PASSWORD)
  end

  def digests = ServiceCalls.digests

  def user_of(actor) = actor.is_a?(ApiToken) ? actor.user : actor

  # What the denial names: the permission, and its subject (a persisted
  # record), or for a refused create only the type; nothing for a call that
  # has no record.
  def assert_denial_event(label, event, permission:, on:)
    assert_equal "access.denied", event.action
    assert_equal permission, event.metadata["permission"], "#{label} refused with the wrong permission key"
    case on
    when Class
      assert_nil event.subject_id, "#{label}: an unsaved record is not an audit subject"
      assert_equal on.polymorphic_name, event.metadata["subject_type"], "#{label} names the wrong type"
    when nil
      assert_nil event.subject_id
      assert_nil event.metadata["subject_type"]
    else
      assert_equal [ on.class.polymorphic_name, on.id ], [ event.subject_type, event.subject_id ], "#{label} names the wrong record"
    end
  end

  # Runs `call` as `actor` on `channel` and asserts the whole refusal: a
  # denial, one audit row naming `permission` on `on`, and no table changed.
  def assert_refused_and_unchanged(label, call:, permission:, on:, actor:, channel:)
    audit_ids = Audit::Event.pluck(:id)
    before = digests

    result = Current.set(actor: actor, channel: channel) { call.call }

    assert_respond_to result, :denied?, "#{label} did not answer with an ApplicationService::Result"
    assert_predicate result, :denied?, "#{label} was not refused (errors: #{result.errors.inspect})"
    assert_not_predicate result, :ok?, "#{label} answered ok for an actor without the right"

    events = Audit::Event.where.not(id: audit_ids).to_a
    assert_equal 1, events.size, "#{label} must write exactly one audit event, an access.denied (got #{events.map(&:action).inspect})"
    assert_equal 1, events.first.occurrences, "#{label} recorded the denial more than once"
    assert_denial_event(label, events.first, permission: permission, on: on)
    assert_equal channel.to_s, events.first.channel
    assert_equal user_of(actor).id, events.first.user_id, "#{label}'s denial is not attributed to the actor"

    changed = before.reject { |table, digest| digest == digests[table] }.keys
    assert_empty changed, "#{label} refused but changed #{changed.join(", ")}"
  end

  # The same call, allowed, rolled back: it must answer ok and change a table
  # (or, for a call that only logs, say so in the factory).
  def assert_changes_something_when_allowed(label, built)
    audit_before = Audit::Event.count
    before = digests
    actor = built[:control_actor]
    result = changed = nil

    ActiveRecord::Base.transaction(requires_new: true) do
      result = Current.set(actor: actor, channel: actor ? :admin : :system) { built[:call].call }
      changed = before.reject { |table, digest| digest == digests[table] }.keys
      # A service that says `# audit: none` names its reason in the factory
      # too (`control_unaudited:`); every other allowed call must be logged.
      if built[:control_unaudited]
        assert_operator built[:control_unaudited].length, :>, 20, "#{label}: control_unaudited needs its reason"
        assert_equal audit_before, Audit::Event.count, "#{label} says it is not audited but recorded an event"
      else
        assert_operator Audit::Event.count, :>, audit_before, "#{label} is allowed but recorded no audit event"
      end
      raise ActiveRecord::Rollback
    end

    assert_predicate result, :ok?, "#{label}'s control run (#{actor ? "as an owner" : "as the trusted actor"}) was refused or failed: #{result.errors.inspect}"
    return if built[:control_audit_only]

    assert_not_empty changed, "#{label}: this call changes nothing even when allowed: make it change something (build what the service writes)"
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
        nobody # created before the snapshot, not by it
        audit_before = Audit::Event.count
        before = digests

        result = Current.set(actor: nobody, channel: :admin) { built[:call].call }

        assert_equal built[:ids].size, result.not_found
        %i[done restored refused failed].each { |list| assert_empty result.public_send(list), "#{klass}##{list}" if result.respond_to?(list) }
        assert_empty result.reasons
        # Not found, never forbidden: no denial is recorded either. Each post
        # that WOULD have been acted on is authorized and audited by the
        # single-record service the bulk one runs.
        assert_equal audit_before, Audit::Event.count, "#{klass} wrote an audit event for ids it could not read"
        assert_equal before, digests
      end

      # A reader may read the posts, so they are found; what they may not do
      # is refused by the single-record service, once per post, with its own
      # `access.denied`. Posts::BulkRestore loads through the delete right,
      # which a reader lacks, so for it everything is still not found.
      test "#{klass} for a reader" do
        reader = users(:reader)
        built = ServiceCalls.for(klass, self)
        audit_ids = Audit::Event.pluck(:id)
        before = digests
        actions = klass == Posts::Bulk ? %w[publish trash] : [ nil ]

        actions.each do |action|
          result = Current.set(actor: reader, channel: :admin) do
            action ? Posts::Bulk.call(action: action, ids: built[:ids]) : built[:call].call
          end

          if klass == Posts::Bulk
            assert_equal built[:ids].sort, result.refused.map(&:id).sort, "#{action}: every readable post is refused"
            assert_empty result.done
            assert_equal 0, result.not_found
          else
            assert_equal built[:ids].size, result.not_found
            assert_empty result.refused
          end
        end

        events = Audit::Event.where.not(id: audit_ids)
        if klass == Posts::Bulk
          assert_equal([ "access.denied" ] * built[:ids].size * actions.size, events.pluck(:action), "one denial per post and action, recorded by the single-record service")
          assert_equal (built[:posts].map(&:id) * actions.size).sort, events.pluck(:subject_id).sort
        else
          assert_empty events
        end
        assert_equal before, digests
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
        assert_refused_and_unchanged(label, call: built[:call], permission: built[:permission], on: built[:on],
          actor: nobody, channel: :admin)
      end

      test "#{label} changes something when allowed" do
        assert_changes_something_when_allowed(label, ServiceCalls.for(klass, self, variant: variant))
      end

      next unless ServiceCalls::MCP_REACHABLE.key?(klass.name)

      # A token is judged on its group AND its user. Each half is tested
      # alone: an Admin-group token of a user with no grants (the user half
      # refuses), and a read-only-group token of an owner (the group half).
      test "#{label} refuses a token of a user with no grants" do
        built = ServiceCalls.for(klass, self, variant: variant)
        token = ApiToken.generate!(nobody, group: access_control_groups(:admin)).first
        assert_refused_and_unchanged("#{label} by token", call: built[:call], permission: built[:permission], on: built[:on],
          actor: token, channel: :mcp)
      end

      test "#{label} refuses a read-only token of an owner" do
        built = ServiceCalls.for(klass, self, variant: variant)
        token = ApiToken.generate!(users(:one), group: access_control_groups(:read_only)).first
        assert_refused_and_unchanged("#{label} by read-only token", call: built[:call], permission: built[:permission], on: built[:on],
          actor: token, channel: :mcp)
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
      token = ApiToken.generate!(built[:owner], group: access_control_groups(:admin)).first
      audit_ids = Audit::Event.pluck(:id)
      before = digests

      result = Current.set(actor: token, channel: :mcp) { built[:own].call }

      assert_predicate result, :denied?, "#{klass} let a token act on its user's own record (errors: #{result.errors.inspect})"
      assert_equal [ "access.denied" ], Audit::Event.where.not(id: audit_ids).pluck(:action)
      assert_equal before, digests
    end

    # The manager's side: a holder of the right (an Admin) acting on someone
    # else's record.
    manager_may = ServiceCalls::SELF_SERVICE.fetch(klass.name)[:manager_may]
    test "#{klass} #{manager_may ? "lets" : "refuses"} a manager acting on someone else's record" do
      built = ServiceCalls.for(klass, self)
      manager = users(:two)

      if manager_may
        audit_ids = Audit::Event.pluck(:id)
        result = Current.set(actor: manager, channel: :admin) { built[:call].call }

        assert_predicate result, :ok?, "#{klass} refused a manager: #{result.errors.inspect}"
        events = Audit::Event.where.not(id: audit_ids).to_a
        assert_includes events.map(&:action), built[:own_event]
        assert_not_includes events.map(&:action), "access.denied"
        assert(events.all? { |event| event.user_id == manager.id })
      else
        assert_refused_and_unchanged("#{klass} by a manager", call: built[:call], permission: built[:permission], on: built[:on],
          actor: manager, channel: :admin)
      end
    end
  end

  test "the services are exactly the expected ones" do
    names = self.class.services.map(&:name)
    assert_empty names - EXPECTED_SERVICES, "services with no entry in EXPECTED_SERVICES (add them, with a factory)"
    assert_empty EXPECTED_SERVICES - names, "EXPECTED_SERVICES names services that no longer exist"
  end

  test "every exemption and factory names a real service" do
    names = self.class.services.map(&:name)
    (ServiceCalls::SELF_SERVICE.keys + ServiceCalls::OWN_RESULT.keys + ServiceCalls::FACTORIES.keys + ServiceCalls::MCP_REACHABLE.keys +
      ServiceCalls::VARIANTS.keys).each do |name|
      assert_includes names, name, "#{name} in test/support/service_calls.rb is not an ApplicationService"
    end
  end
end
