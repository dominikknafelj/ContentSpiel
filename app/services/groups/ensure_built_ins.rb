module Groups
  # Makes the built-in groups a database lacks (Admin, Editor, Author, Read
  # only: `AccessControl::Seeds::BUILT_IN`), each with the grants it starts
  # with, and leaves every group that exists exactly as it is.
  #
  # WHY IT EXISTS. The groups were made by a data migration
  # (`SeedAccessControlGroups`) and by development's seed, and by nothing
  # else. A database is not built by running migrations: `db:prepare`,
  # `db:setup`, `db:schema:load`, and since Rails 8 `db:migrate` on an empty
  # database too, all load `db/schema.rb`, which carries tables and no rows.
  # So a new site had no group at all: the Groups screen was empty and the
  # setup wizard's token step, which looks the Admin group up by name, was a
  # 404. `db/schema.rb` cannot carry a row any more than it can carry a
  # trigger (`config/initializers/db_triggers.rb`), so the rows a site needs
  # are made here, and this is called from the two places a new site passes:
  #
  # - `db/seeds.rb`, in every environment, which `db:prepare` (the
  #   container's entrypoint) and `db:setup` run after loading the schema,
  #   and which `bin/rails db:seed` runs by hand on a site that was set up
  #   before this existed;
  # - the setup wizard, before any step past the token writes
  #   (`SetupController#ensure_built_in_groups`), for a database built with
  #   `db:schema:load` alone, which runs no seed.
  #
  # ONLY WHAT IS MISSING, BY NAME. A built-in group can be edited and never
  # deleted or renamed, so its grants are the site's own after the first day:
  # an owner who took `posts.delete` from Editor must not get it back at the
  # next deploy. That is the difference from `AccessControl::Seeds
  # .ensure_built_in_groups!`, which also adds a missing grant to a group
  # that exists and is for the migration alone. A group somebody made by
  # hand under one of the four names (on a site that had none) counts as
  # there: names are unique whatever their case, and it is theirs. Running
  # this twice writes nothing the second time, and with nothing missing it
  # asks for no right and records nothing.
  #
  # Needs `groups.manage`, like `Groups::Save` for a new group. The seed file
  # and the wizard's steps before the first account run it as the trusted
  # nil actor, the later steps as the signed-in owner. One `group.created`
  # per group made. `record` is the list of groups it made.
  class EnsureBuiltIns < ApplicationService
    def initialize(actor: Current.actor)
      @actor = actor
    end

    def call
      names = missing_names
      return success([]) if names.empty?

      blank = AccessControl::Group.new
      return denied("groups.manage", blank) unless authorize!("groups.manage", blank)

      # `requires_new`: the unique index on lower(name) is what settles two
      # of these running at once (two containers starting, two wizard
      # posts); the loser's savepoint goes and its caller's transaction, if
      # there is one, is left usable.
      success(AccessControl::Group.transaction(requires_new: true) { names.map { |name| create(name) } })
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      # Somebody else made them between the read and the write (the index
      # says so, or the name's own validation, whichever saw it first): they
      # are there, which is all that was asked. Anything else that is
      # invalid is this code's fault and is not swallowed.
      raise if missing_names.any?

      success([])
    end

    private

    # Compared without case, as the unique index compares them. Read whole:
    # a site has a handful of groups.
    def missing_names
      present = AccessControl::Group.pluck(:name).map(&:downcase)
      AccessControl::Seeds::BUILT_IN.keys.reject { |name| present.include?(name.downcase) }
    end

    def create(name)
      group = AccessControl::Group.create!(name: name, description: AccessControl::Seeds::BUILT_IN.fetch(name)[:description], built_in: true)
      # Read before the grants are written, like `Groups::Save#record_changes`.
      changes = Audit::Snapshot.field_changes_for(group)
      AccessControl::Seeds.grants_of(name).each { |grant| group.grants.create!(permission: grant[:permission], scope: grant[:scope]) }
      record_event("group.created", subject: group, field_changes: changes)
      group
    end
  end
end
