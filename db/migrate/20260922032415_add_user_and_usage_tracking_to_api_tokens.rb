# Binds each token to the admin it authenticates as for MCP purposes (design
# spec section 10 revisited -- v1 shipped a single global token with no user
# at all, "no per-client scoping"; an MCP client now inherits the full
# authoring identity of whichever User's token it holds, so attributing and
# independently revoking that access is worth the FK even with one admin
# today). `last_used_at`/`last_used_ip` mirror Session's own `ip_address`
# tracking, for the same reason: visibility into a credential used
# unattended, not just at creation.
class AddUserAndUsageTrackingToApiTokens < ActiveRecord::Migration[8.1]
  def change
    add_reference :api_tokens, :user, null: false, foreign_key: true
    add_column :api_tokens, :last_used_at, :datetime
    add_column :api_tokens, :last_used_ip, :string
  end
end
