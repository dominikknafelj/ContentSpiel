# A page's type (`page_type`, an integer enum: 0 standard, 1 landing) becomes
# its template, a NAME the theme declares, kept in `pages.settings`
# (`{"template" => "landing"}`; `{}` is the theme's first template, which is
# what a standard page was).
#
# FROZEN LOGIC, CALLING NO APPLICATION CLASS, as the first copies' migration
# is: plain SQL on the tables as they are at this version, so it means the
# same on any day it runs.
#
# EVERY COPY OF A PAGE is rewritten, not only the current one: a scheduled
# page's pending copy, a superseded copy and a copy the first copies'
# migration took all lose `fields.page_type` and gain `fields.settings`, in
# whatever form the copy stored the type (the enum's key, "landing", which
# `Publishing::Snapshot.of` wrote, or its number). A copy with no
# `page_type` at all is left as it is. This is the successor
# `test/models/publishing/first_copies_migration_test.rb` asks for when a
# copy's shape changes on purpose, and the one rewrite of a copy's content
# besides `Publishing::Version.repoint_tag!`: after it every copy has one
# shape, and nothing reads the old one.
#
# Nothing is drawn differently afterwards, so the public content version does
# not move; `updated_at` does not move either. The audit log is not rewritten:
# it is append-only, and an old event's snapshot keeps `page_type` as history.
# It inserts no row (a schema-loaded database has `settings` with its default).
class ReplacePageTypeWithPageSettings < ActiveRecord::Migration[8.1]
  def up
    add_column :pages, :settings, :jsonb, default: {}, null: false
    rewrite_pages
    rewrite_copies
    remove_column :pages, :page_type
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "a page's template is a name now; the integer page type is not kept"
  end

  # Public so that the test can run the steps. Each is idempotent.
  def rewrite_pages
    execute(<<~SQL) # sql: a frozen backfill on the table as it is at this version, naming no model
      UPDATE pages SET settings = '{"template": "landing"}'::jsonb WHERE page_type = 1
    SQL
  end

  def rewrite_copies
    execute(<<~SQL) # sql: a frozen rewrite of every page copy's jsonb, current, pending and superseded alike
      UPDATE published_versions
      SET snapshot = jsonb_set(
        snapshot,
        '{fields}',
        ((snapshot -> 'fields') - 'page_type') || jsonb_build_object(
          'settings',
          CASE WHEN snapshot -> 'fields' -> 'page_type' IN ('"landing"'::jsonb, '1'::jsonb)
            THEN '{"template": "landing"}'::jsonb
            ELSE '{}'::jsonb
          END
        )
      )
      WHERE record_type = 'Page' AND snapshot -> 'fields' ? 'page_type'
    SQL
  end
end
