# The database backstop for decision D2 (a token name is unique per user
# among that user's ACTIVE tokens, case-insensitively). The model validation
# alone is a check-then-insert, so a double submit or two tabs could both pass
# it and leave two active tokens with one name, making "via <name>" ambiguous.
# Partial on `revoked_at IS NULL`, so a revoked token's name is free again.
# Safe on existing data: the backfill (AddNameToApiTokens) named each user's
# tokens "Token 1", "Token 2", ... by construction unique per user.
class AddUniqueActiveNameIndexToApiTokens < ActiveRecord::Migration[8.1]
  def change
    add_index :api_tokens, "user_id, lower(name)", unique: true, where: "revoked_at IS NULL",
      name: "index_api_tokens_on_user_and_lower_name_active"
  end
end
