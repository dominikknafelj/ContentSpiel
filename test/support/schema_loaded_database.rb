# The state `db/schema.rb` leaves: every table, no row. It is how every new
# database starts: `db:prepare` (the container's entrypoint), `db:setup`,
# `db:schema:load`, and since Rails 8 `db:migrate` on an empty database, all
# load the schema file, and no migration's data step runs. The test database
# is built the same way and then filled by the fixtures, which is why nothing
# noticed that a new site had no groups: the fixtures hold the four built-in
# groups a migration once inserted.
#
# `empty_as_after_a_schema_load` takes away what the fixtures put where a
# schema load leaves nothing and the application reads at its first start:
# the groups with their grants and memberships (and the tokens that point at
# them), the users, the site settings row and the content version's row. The
# test's transaction puts them back.
module SchemaLoadedDatabase
  def empty_as_after_a_schema_load
    ApiToken.delete_all
    AccessControl::Membership.delete_all
    AccessControl::Grant.delete_all
    AccessControl::Group.delete_all
    User.delete_all
    SiteSetting.delete_all
    PublicSite::Version.delete_all
    # What the two rows' callbacks would have reset, had they run.
    Current.site = nil
    Setup.reset!
    SetupController::RATE_LIMIT_STORE.clear
  end

  # A group as `[name, built_in, [[permission, scope], ...]]`, for comparing
  # two ways of making them.
  def groups_as_data
    AccessControl::Group.order(:name).map do |group|
      [ group.name, group.built_in, group.grants.order(:permission).pluck(:permission, :scope) ]
    end
  end
end
