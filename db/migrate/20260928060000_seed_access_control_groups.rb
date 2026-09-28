# The data half of access control (design spec §6): seeds the four
# built-in groups and backfills every existing user, token and post onto
# the columns the previous migration (`CreateAccessControl`) just added.
# See `AccessControl::Seeds`'s own comment for why calling straight through
# to the real app models is acceptable here, unlike a typical Rails data
# migration.
#
# Tightens `api_tokens.group_id` to NOT NULL only after the backfill has
# given every row a value -- see that column's comment in
# `CreateAccessControl`.
class SeedAccessControlGroups < ActiveRecord::Migration[8.1]
  def up
    AccessControl::Seeds.ensure_built_in_groups!
    AccessControl::Seeds.backfill!

    change_column_null :api_tokens, :group_id, false
  end

  def down
    change_column_null :api_tokens, :group_id, true
  end
end
