# Media library final fix wave (C1): the `rich_text` rows of `media_usages`
# for bodies that already embedded a library image before the index
# existed. `MoveImagesIntoMediaLibrary` now adds them itself, but a
# database that ran that migration before the fix never got them -- every
# such image reads as "Unused" there, and deleting it purges a file a live
# body still shows (a rich-text reference has no FK to stop it).
#
# The same SQL as `MoveImagesIntoMediaLibrary#add_rich_text_usages` (see
# its comment for each step), copied rather than shared: a migration is
# frozen history, and loading one migration file from another would load
# its class twice. Additive and idempotent -- `ON CONFLICT DO NOTHING` on
# the (`NULLS NOT DISTINCT`) unique index, never a delete -- so on a
# database the fixed migration already covered, or one whose services have
# kept the index current since, it changes nothing. `bin/rails
# media:reindex` does the same through `Media::UsageIndex` (and also drops
# stale rows); this is what makes the fix reach an install that only runs
# `db:migrate`.
#
# `down` is a no-op: the rows describe the bodies as they are, and removing
# them would bring back exactly the "Unused but embedded" state this fixes.
class BackfillRichTextMediaUsages < ActiveRecord::Migration[8.1]
  OWNERS = { "Post" => "posts", "ContentBlock" => "content_blocks" }.freeze

  def up
    OWNERS.each do |owner_type, table|
      added = connection.execute(<<~SQL).cmd_tuples
        INSERT INTO media_usages (media_asset_id, owner_type, owner_id, role, locale, created_at, updated_at)
        SELECT DISTINCT media_assets.id, '#{owner_type}', owners.id, 'rich_text', bodies.locale, now(), now()
        FROM #{table} owners
        CROSS JOIN LATERAL jsonb_each(CASE WHEN jsonb_typeof(owners.body) = 'object' THEN owners.body ELSE '{}'::jsonb END) AS bodies(locale, document)
        CROSS JOIN LATERAL jsonb_path_query(bodies.document, 'lax $.** ? (@.type == "image").attrs.asset_id') AS refs(value)
        JOIN media_assets ON media_assets.id = CASE WHEN refs.value #>> '{}' ~ '^(0|[1-9][0-9]{0,17})$' THEN (refs.value #>> '{}')::bigint END
        WHERE jsonb_typeof(bodies.document) = 'object'
        ON CONFLICT DO NOTHING
      SQL
      say "#{owner_type}: added #{added} rich_text usage row(s)"
    end
  end

  def down
  end
end
