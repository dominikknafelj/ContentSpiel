# The second half of retiring ActionText (tiptap design spec §5): drops
# `action_text_rich_texts` and `youtube_embeds` (the `YoutubeEmbed`
# attachable is replaced by the `youtube` node), plus the Active Storage
# attachment rows that tied blobs to ActionText records -- the blobs
# themselves stay: an image the importer converted is now attached to a
# `MediaAsset` instead (the same blob, re-attached, spec §5).
#
# Guarded: `up` refuses to run while any ActionText body with visible
# content -- text, or an attachment -- belongs to a post/block whose JSON
# `body` has nothing for that language, i.e. while
# `rich_text:migrate_from_action_text` hasn't converted it yet. "Nothing"
# mirrors `RichText::Document#blank?` in SQL (no non-empty text node, no
# image or youtube node), so a locale an editor left blank in CS Studio
# still counts as unconverted. Bodies with nothing visible (Trix's empty
# `<div><br></div>`, markup that's only a script) and rows whose record is
# gone have nothing to lose and don't block.
#
# `FORCE_DROP_ACTION_TEXT=1` skips the guard (fix round 1): a body whose
# only content is something the importer can't map (a remote attachment, a
# missing blob, text inside a dropped `<script>`) converts to a blank
# document, which the guard can't tell apart from "not converted yet" -- so
# without an override `db:migrate` could refuse forever. The task lists
# those rows under "Imported blank"; check them, then force the drop.
#
# Plain SQL throughout, not the
# app's models -- ActionText's models are already gone from the code this
# runs with.
class DropActionText < ActiveRecord::Migration[8.1]
  RECORD_TABLES = { "Post" => "posts", "ContentBlock" => "content_blocks" }.freeze

  # Visible text once `<script>`/`<style>` blocks and every tag are
  # stripped, or an attachment tag (which carries no text of its own). A
  # script/style block is only stripped when its contents hold no `<` at
  # all -- errs towards "has content", which only ever blocks the drop,
  # never lets it lose anything. (No lazy `.*?`: in a Postgres regex a
  # later non-greedy quantifier doesn't make the match non-greedy when an
  # earlier one is greedy.)
  HAS_CONTENT_SQL = <<~SQL.squish
    (rt.body ILIKE '%<action-text-attachment%'
      OR regexp_replace(
           regexp_replace(rt.body, '<(script|style)[^>]*>[^<]*</(script|style)[^>]*>', '', 'gi'),
           '<[^>]*>', '', 'g') ~ '[^[:space:]]')
  SQL

  # `!RichText::Document#blank?` over one locale's document -- false (not
  # NULL) when the locale has no document at all.
  DOCUMENT_HAS_CONTENT_SQL = <<~SQL.squish
    COALESCE(jsonb_path_exists(t.body -> rt.locale,
      '$.** ? (@.type == "image" || @.type == "youtube" || (@.type == "text" && @.text like_regex "[^[:space:]]"))'), false)
  SQL

  def up
    if table_exists?(:action_text_rich_texts) && ENV["FORCE_DROP_ACTION_TEXT"] != "1"
      unconverted = RECORD_TABLES.sum do |record_type, table|
        select_value(<<~SQL.squish).to_i
          SELECT COUNT(*) FROM action_text_rich_texts rt
          JOIN #{table} t ON t.id = rt.record_id
          WHERE rt.record_type = #{connection.quote(record_type)} AND rt.name = 'body'
            AND #{HAS_CONTENT_SQL} AND NOT #{DOCUMENT_HAS_CONTENT_SQL}
        SQL
      end

      if unconverted.positive?
        raise "#{unconverted} ActionText #{"body".pluralize(unconverted)} haven't been converted yet: " \
          "run bin/rails rich_text:migrate_from_action_text first, then bin/rails db:migrate again " \
          "(if the task lists them as imported blank and you've checked them, migrate with FORCE_DROP_ACTION_TEXT=1)"
      end
    end

    execute "DELETE FROM active_storage_attachments WHERE record_type = 'ActionText::RichText'"
    drop_table :action_text_rich_texts, if_exists: true
    drop_table :youtube_embeds, if_exists: true
  end

  # Restores the two tables' structure (as `action_text:install` and the
  # YouTube-embed migration created them) -- but not their data: every
  # ActionText body and YouTube embed row is gone for good once `up` has
  # run. Rolling back gives an empty ActionText, which is only useful to get
  # back to a schema the previous code can boot against.
  def down
    create_table :youtube_embeds do |t|
      t.string :video_id, null: false
      t.timestamps
    end
    add_index :youtube_embeds, :video_id, unique: true

    create_table :action_text_rich_texts do |t|
      t.string :name, null: false
      t.text :body
      t.references :record, null: false, polymorphic: true, index: false
      t.string :locale, null: false
      t.timestamps
    end
    add_index :action_text_rich_texts, [ :record_type, :record_id, :name, :locale ],
      name: :index_action_text_rich_texts_uniqueness, unique: true
  end
end
