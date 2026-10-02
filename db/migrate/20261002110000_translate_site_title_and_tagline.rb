# Translation helpers spec §5: the site title and tagline become Mobility
# jsonb columns (`{ locale => value }`), like every other translated column
# -- the existing string moving into the site's own default locale, the
# language it was typed in (the setup wizard and Settings only ever had the
# one field).
#
# `down` restores the default-locale string. The title is `null: false`, and
# a row whose default language has no title of its own (one written around
# `SiteSetting`'s validation) would otherwise fail the type change, so it
# falls back to the first other non-blank language's title, then to an empty
# string -- losing a translation on rollback is expected, losing the only
# title there is isn't. `jsonb_path_query_first`, not a subquery: Postgres
# refuses subqueries in an `ALTER COLUMN ... USING` expression.
class TranslateSiteTitleAndTagline < ActiveRecord::Migration[8.1]
  def up
    change_column :site_settings, :title, :jsonb, null: false, using: <<~SQL.squish
      CASE WHEN NULLIF(BTRIM(title), '') IS NULL THEN '{}'::jsonb ELSE jsonb_build_object(default_locale, title) END
    SQL
    change_column_default :site_settings, :title, from: nil, to: {}

    change_column :site_settings, :tagline, :jsonb, using: <<~SQL.squish
      CASE WHEN NULLIF(BTRIM(tagline), '') IS NULL THEN '{}'::jsonb ELSE jsonb_build_object(default_locale, tagline) END
    SQL
    change_column_default :site_settings, :tagline, from: nil, to: {}
    change_column_null :site_settings, :tagline, false
  end

  def down
    change_column_default :site_settings, :title, from: {}, to: nil
    change_column :site_settings, :title, :string, null: false, using: <<~SQL.squish
      COALESCE(NULLIF(title ->> default_locale, ''), jsonb_path_query_first(title, '$.* ? (@ != "")') #>> '{}', '')
    SQL

    change_column_null :site_settings, :tagline, true
    change_column_default :site_settings, :tagline, from: {}, to: nil
    change_column :site_settings, :tagline, :string, using: "NULLIF(tagline ->> default_locale, '')"
  end
end
