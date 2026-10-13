require "test_helper"
require_relative "../../support/schema_loaded_database"
require_relative "../../support/service_calls"

# `Groups::EnsureBuiltIns`: the built-in groups of a database that was built
# by loading the schema (the service's own comment says why that is every new
# database).
class Groups::EnsureBuiltInsTest < ActiveSupport::TestCase
  include SchemaLoadedDatabase

  NAMES = [ "Admin", "Author", "Editor", "Read only" ].freeze

  test "a schema-loaded database gets the four built-in groups with the grants the migrations gave them, and one event each" do
    empty_as_after_a_schema_load
    assert_equal 0, AccessControl::Group.count

    result = nil
    assert_difference -> { Audit::Event.where(action: "group.created").count }, 4 do
      result = Current.set(channel: :system) { Groups::EnsureBuiltIns.call }
    end

    assert_predicate result, :ok?
    assert_equal NAMES, result.record.map(&:name).sort
    assert_equal NAMES, AccessControl::Group.where(built_in: true).order(:name).pluck(:name)
    made = groups_as_data

    # Admin holds every registered permission, unscoped: what the three
    # later migrations added (`media.manage`, `trash.empty`, `ai.translate`)
    # is among them without being listed anywhere.
    admin = AccessControl::Group.find_by!(name: "Admin")
    assert_equal AccessControl::Permissions.keys.sort, admin.grants.pluck(:permission).sort
    assert(admin.grants.all? { |grant| grant.scope == {} })
    assert_includes AccessControl::Group.find_by!(name: "Editor").grants.pluck(:permission), "media.manage"
    assert_includes AccessControl::Group.find_by!(name: "Editor").grants.pluck(:permission), "ai.translate"
    assert_equal({ "own" => true }, AccessControl::Group.find_by!(name: "Author").grants.find_by!(permission: "posts.edit").scope)

    # And it is what the data migration's own step makes of an empty table.
    AccessControl::Grant.delete_all
    AccessControl::Group.delete_all
    AccessControl::Seeds.ensure_built_in_groups!
    assert_equal groups_as_data, made
  end

  test "running it again writes nothing: no row of any table, no event" do
    empty_as_after_a_schema_load
    Groups::EnsureBuiltIns.call
    before = ServiceCalls.digests
    events = Audit::Event.count

    result = Groups::EnsureBuiltIns.call

    assert_predicate result, :ok?
    assert_empty result.record
    assert_equal before, ServiceCalls.digests
    assert_equal events, Audit::Event.count
  end

  test "a group that exists is left as it is: a grant an owner took away does not come back, and only the missing group is made" do
    editor = access_control_groups(:editor)
    editor.grants.where(permission: "posts.delete").delete_all
    editor.update!(description: "Ours now")
    read_only = access_control_groups(:read_only)
    read_only.grants.delete_all
    read_only.delete
    untouched = groups_as_data.reject { |name, *| name == "Read only" }

    result = Groups::EnsureBuiltIns.call

    assert_equal [ "Read only" ], result.record.map(&:name)
    assert_equal untouched, groups_as_data.reject { |name, *| name == "Read only" }
    assert_not_includes editor.reload.grants.pluck(:permission), "posts.delete"
    assert_equal "Ours now", editor.description
    assert_equal %w[pages.read posts.read], AccessControl::Group.find_by!(name: "Read only").grants.order(:permission).pluck(:permission)
  end

  test "a group somebody made by hand under a built-in name counts as there, whatever its case" do
    empty_as_after_a_schema_load
    theirs = AccessControl::Group.create!(name: "admin", description: "Made by hand")

    result = Groups::EnsureBuiltIns.call

    assert_predicate result, :ok?
    assert_equal [ "Author", "Editor", "Read only" ], result.record.map(&:name).sort
    assert_equal [ theirs ], AccessControl::Group.where(built_in: false).to_a
    assert_empty theirs.reload.grants
  end

  test "someone without groups.manage is refused when a group is missing, and asked nothing when none is" do
    reader = users(:reader)

    quiet = nil
    assert_no_difference "Audit::Event.count" do
      quiet = Current.set(actor: reader, channel: :admin) { Groups::EnsureBuiltIns.call }
    end
    assert_predicate quiet, :ok?

    read_only = access_control_groups(:read_only)
    AccessControl::Membership.where(group: read_only).delete_all
    read_only.grants.delete_all
    read_only.delete

    refused = Current.set(actor: reader, channel: :admin) { Groups::EnsureBuiltIns.call }

    assert_predicate refused, :denied?
    assert_nil AccessControl::Group.find_by(name: "Read only")
    assert_equal "access.denied", Audit::Event.order(:id).last.action
  end
end
