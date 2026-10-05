require "test_helper"
require Rails.root.join("db/migrate/20261005140000_api_tokens_lookup_digest").to_s

# API tokens are looked up by the SHA-256 of the presented value
# (`lookup_digest`, unique) instead of a bcrypt scan. A bcrypt digest can't be
# turned into a SHA-256, so every token that exists before the migration is
# revoked and given the placeholder "revoked:<id>", which no raw token can
# produce. The column exists on the test database, so each test rolls the
# migration back inside its own transaction (Postgres DDL is transactional),
# inserts "before" rows raw and runs `up` again.
class ApiTokensLookupDigestMigrationTest < ActiveSupport::TestCase
  setup do
    ApiToken.delete_all
    ActiveRecord::Migration.suppress_messages { ApiTokensLookupDigest.new.migrate(:down) }
    ApiToken.reset_column_information
  end

  teardown { ApiToken.reset_column_information }

  def insert_token(user, name, revoked_at: nil)
    ApiToken.insert_all!([ { user_id: user.id, group_id: access_control_groups(:admin).id, name: name, token_digest: "$2a$12$notarealdigest",
                             revoked_at: revoked_at, created_at: Time.current, updated_at: Time.current } ], returning: %w[id]).rows.flatten.first
  end

  def migrate_up
    previous = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = true
    out, = capture_io { ApiTokensLookupDigest.new.migrate(:up) }
    out
  ensure
    ActiveRecord::Migration.verbose = previous
    ApiToken.reset_column_information
  end

  test "an active token is revoked, gets a placeholder digest and the count is printed" do
    active = insert_token(users(:one), "Active one")
    other = insert_token(users(:two), "Active two")
    already = insert_token(users(:one), "Old", revoked_at: 3.days.ago)

    out = migrate_up

    assert_not_nil ApiToken.find(active).revoked_at
    assert_not_nil ApiToken.find(other).revoked_at
    assert_equal "revoked:#{active}", ApiToken.find(active).lookup_digest
    assert_equal "revoked:#{already}", ApiToken.find(already).lookup_digest
    assert_in_delta 3.days.ago.to_f, ApiToken.find(already).revoked_at.to_f, 5, "an already revoked token keeps its time"
    assert_includes out, "2 active API tokens revoked"
    assert_not_includes out, "Active one"
    assert_not_includes out, "$2a$"
  end

  test "the column is required and unique, and token_digest is gone" do
    insert_token(users(:one), "Active one")
    migrate_up

    assert_not ApiToken.columns_hash["lookup_digest"].null
    assert_not_includes ApiToken.column_names, "token_digest"
    assert ActiveRecord::Base.connection.index_exists?(:api_tokens, :lookup_digest, unique: true)
  end

  test "no raw token authenticates against a placeholder" do
    id = insert_token(users(:one), "Active one")
    migrate_up

    assert_nil ApiToken.authenticate("revoked:#{id}")
  end

  test "down restores token_digest and drops lookup_digest" do
    migrate_up
    ActiveRecord::Migration.suppress_messages { ApiTokensLookupDigest.new.migrate(:down) }
    ApiToken.reset_column_information

    assert_includes ApiToken.column_names, "token_digest"
    assert_not_includes ApiToken.column_names, "lookup_digest"
  end
end
