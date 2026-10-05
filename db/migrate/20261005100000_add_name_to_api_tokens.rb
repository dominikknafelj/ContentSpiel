# API tokens get names (round 3 decision D2): a person picks the token out
# of a list, and the audit log says "via <name>". Existing tokens are named
# "Token 1", "Token 2", ... per user, in id order. Added nullable, backfilled
# in one statement, then made NOT NULL, so the table is never invalid.
class AddNameToApiTokens < ActiveRecord::Migration[8.1]
  def up
    add_column :api_tokens, :name, :string
    execute <<~SQL
      UPDATE api_tokens SET name = numbered.name
      FROM (
        SELECT id, 'Token ' || ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY id) AS name
        FROM api_tokens
      ) AS numbered
      WHERE api_tokens.id = numbered.id
    SQL
    change_column_null :api_tokens, :name, false
  end

  def down
    remove_column :api_tokens, :name
  end
end
