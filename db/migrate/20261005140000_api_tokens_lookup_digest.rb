# An API token is looked up by an indexed equality on the SHA-256 of the
# presented value (`lookup_digest`, unique) rather than by a bcrypt compare
# against every active token. A token is 256 random bits, so a fast digest
# loses nothing a slow one would have protected.
#
# A bcrypt digest can't be turned into a SHA-256 -- the raw token is not
# stored anywhere -- so every token that exists is revoked here and its
# `lookup_digest` is the placeholder "revoked:<id>", which no raw token can
# hash to (a SHA-256 hex digest is 64 hex characters). Revoking only frees
# names (the unique-name index covers active tokens), it can't clash. The
# output says how many active tokens were revoked, by count only. `down`
# restores the old column with an unusable value for every row: those tokens
# stay revoked.
class ApiTokensLookupDigest < ActiveRecord::Migration[8.1]
  def up
    add_column :api_tokens, :lookup_digest, :string

    revoked = select_value(<<~SQL).to_i
      WITH revoked AS (
        UPDATE api_tokens SET revoked_at = NOW(), updated_at = NOW() WHERE revoked_at IS NULL RETURNING id
      ) SELECT COUNT(*) FROM revoked
    SQL
    execute "UPDATE api_tokens SET lookup_digest = 'revoked:' || id"

    change_column_null :api_tokens, :lookup_digest, false
    add_index :api_tokens, :lookup_digest, unique: true
    remove_column :api_tokens, :token_digest

    say "#{revoked} active API tokens revoked: their digests can't be converted, create new tokens under AI assistant"
  end

  def down
    add_column :api_tokens, :token_digest, :string
    execute "UPDATE api_tokens SET token_digest = 'revoked', revoked_at = COALESCE(revoked_at, NOW())"
    change_column_null :api_tokens, :token_digest, false
    remove_index :api_tokens, :lookup_digest
    remove_column :api_tokens, :lookup_digest
  end
end
