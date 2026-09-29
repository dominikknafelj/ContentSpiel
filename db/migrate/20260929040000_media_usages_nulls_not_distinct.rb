# Media library Task 3, fix round 1 (I1 follow-up): closes the gap the
# first fix round's `insert_all(..., unique_by:)` conflict-skip left open.
#
# Postgres's default unique index treats `NULL` as distinct from every
# other `NULL` -- two `media_usages` rows with the same `media_asset_id`/
# `owner_type`/`owner_id`/`role` but both `locale IS NULL` (every `hero`
# and `block_image` row, which are never per-locale) were never actually
# unique-constrained against each other, so `ON CONFLICT` could never
# detect, and therefore never skip, a duplicate `hero`/`block_image` row --
# only a `rich_text` row (a real, non-null `locale`) was ever protected.
#
# `NULLS NOT DISTINCT` (Postgres 15+; this app runs 17, per the CLAUDE.md
# setup instructions -- `docker compose up -d` pins the image) makes two
# `NULL`s in an indexed column compare equal for uniqueness purposes, the
# same way any other equal value pair would. That's the one column-level
# change needed for `Media::UsageIndex#insert_rows`'s conflict-skip to
# genuinely cover every role, not just `rich_text`.
#
# A plain index option, not achievable by editing the original migration
# after the fact (global constraints: migrations already run are never
# edited in place) -- this drops and re-creates the same unique index with
# that one option added. `remove_index` is given the column list, not the
# original migration's Postgres-generated, hash-suffixed name
# (`db/schema.rb`'s own `idx_on_..._b9b1b045d0`): Rails resolves a column
# list to whichever index actually matches it, the same way `insert_all`'s
# own `unique_by:` does.
class MediaUsagesNullsNotDistinct < ActiveRecord::Migration[8.1]
  UNIQUE_COLUMNS = [ :media_asset_id, :owner_type, :owner_id, :role, :locale ].freeze

  def up
    remove_index :media_usages, UNIQUE_COLUMNS
    add_index :media_usages, UNIQUE_COLUMNS, unique: true, nulls_not_distinct: true
  end

  def down
    remove_index :media_usages, UNIQUE_COLUMNS
    add_index :media_usages, UNIQUE_COLUMNS, unique: true
  end
end
