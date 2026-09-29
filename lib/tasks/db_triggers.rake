# Re-applies the database triggers `db/schema.rb` can't carry (see
# config/initializers/db_triggers.rb, which already applies them after every
# schema load -- `db:schema:load`, `db:reset`, `db:prepare`,
# `db:test:prepare` and parallel test workers). This task is the manual
# escape hatch for a database that was built some other way (a restored
# dump, a hand-run `psql` schema), and is idempotent.
namespace :db do
  namespace :triggers do
    desc "Apply the database triggers in db/triggers/ to the current database"
    task apply: :environment do
      DbTriggers.apply!(ActiveRecord::Base.connection)
    end
  end
end
