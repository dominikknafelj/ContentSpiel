# The three FKs into `media_assets` were created `on_delete: :restrict`.
# Postgres 18 reports a violated RESTRICT with its own SQLSTATE (23001
# `restrict_violation`, "violates RESTRICT setting of foreign key
# constraint") instead of 23503 `foreign_key_violation`, and Rails maps only
# 23503 to `ActiveRecord::InvalidForeignKey` -- so on 18 a delete of an
# in-use asset surfaced as a bare `StatementInvalid`, slipping past every
# `rescue ActiveRecord::InvalidForeignKey` (`Media::Destroy`, the save
# services). CI's unpinned `postgres` image caught it; local Postgres 17
# still said 23503.
#
# The default action (NO ACTION) gives the same guarantee here -- none of
# these constraints is deferrable, so NO ACTION is checked at the end of
# the statement, and nothing in between could make the reference valid --
# while raising 23503 on every Postgres version.
class MediaForeignKeysNoAction < ActiveRecord::Migration[8.1]
  FOREIGN_KEYS = [
    [ :media_usages, :media_asset_id ],
    [ :pages, :hero_media_asset_id ],
    [ :content_blocks, :media_asset_id ]
  ].freeze

  def up
    replace(on_delete: nil)
  end

  def down
    replace(on_delete: :restrict)
  end

  private

  def replace(on_delete:)
    FOREIGN_KEYS.each do |table, column|
      remove_foreign_key table, :media_assets, column: column
      add_foreign_key table, :media_assets, column: column, on_delete: on_delete
    end
  end
end
