require "test_helper"
require Rails.root.join("db/migrate/20261005100000_add_name_to_api_tokens").to_s

# Round 3 Task 2: existing tokens are named "Token 1", "Token 2", ... per
# user in id order. The column already exists (and is NOT NULL) on the test
# database, so each test rolls the migration back inside the test's own
# transaction (Postgres DDL is transactional), inserts the "before" rows
# with `insert_all` and runs `up` again.
class AddNameToApiTokensMigrationTest < ActiveSupport::TestCase
  test "up names each user's existing tokens by id, per user, and makes the column required" do
    ApiToken.delete_all
    ActiveRecord::Migration.suppress_messages { AddNameToApiTokens.new.migrate(:down) }
    ApiToken.reset_column_information

    group = access_control_groups(:admin)
    rows = [ users(:one), users(:one), users(:two), users(:one) ].map do |user|
      { user_id: user.id, group_id: group.id, token_digest: "digest", created_at: Time.current, updated_at: Time.current }
    end
    ids = ApiToken.insert_all(rows, returning: %w[id]).rows.flatten

    ActiveRecord::Migration.suppress_messages { AddNameToApiTokens.new.migrate(:up) }
    ApiToken.reset_column_information

    names = ApiToken.where(id: ids).order(:id).pluck(:user_id, :name)
    assert_equal [ [ users(:one).id, "Token 1" ], [ users(:one).id, "Token 2" ], [ users(:two).id, "Token 1" ], [ users(:one).id, "Token 3" ] ], names
    assert_not ApiToken.columns_hash["name"].null
  ensure
    ApiToken.reset_column_information
  end
end
