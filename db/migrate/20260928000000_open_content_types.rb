# Open types (spec §4.1): block_type/content_type stop being closed integer
# enums and become plain strings checked against BlockTypes/ContentTypes at
# the model layer instead of at the database layer. ContentBlock also gets a
# polymorphic owner in place of the page-only `page_id`, so a future owner
# (a snippet, say) can hold blocks the same way a Page does.
#
# Greenfield, no production (global constraints): this rewrites the columns
# outright rather than layering a compatibility shim on top of the enum, and
# `bin/rails db:reset` is expected to follow in dev -- there is no backfill
# for existing rows.
class OpenContentTypes < ActiveRecord::Migration[8.1]
  def up
    # No backfill from `page_id` to `owner_type`/`owner_id` (global
    # constraints: greenfield, no compatibility shims) -- existing rows are
    # dropped outright rather than migrated, same as the dev data `db:reset`
    # clears right after this runs. A NOT NULL `owner_type`/`owner_id` added
    # onto a populated table would otherwise fail outright on Postgres.
    execute "DELETE FROM content_blocks"

    remove_reference :content_blocks, :page, index: true, foreign_key: true
    add_reference :content_blocks, :owner, polymorphic: true, null: false, index: false
    add_index :content_blocks, [ :owner_type, :owner_id, :position ]
    change_column :content_blocks, :block_type, :string, null: false, default: nil, using: "block_type::text"

    # Untranslated field values already live in `settings`; this adds the
    # translated half (`{ locale => { key => value } }`) a type's
    # `translated: true` fields write into.
    add_column :content_blocks, :translated_settings, :jsonb, null: false, default: {}

    change_column :posts, :content_type, :string, null: false, default: nil, using: "content_type::text"
    add_index :posts, :content_type

    # Same shape as `content_blocks.translated_settings`, for a content
    # type's translated fields over `metadata`.
    add_column :posts, :translated_metadata, :jsonb, null: false, default: {}
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
