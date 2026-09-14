# One table for all three block types (rich_text/image/post_list), the same
# single-model-plus-enum shape `posts` uses -- see page-tree design spec
# section 3.
class CreateContentBlocks < ActiveRecord::Migration[8.1]
  def change
    create_table :content_blocks do |t|
      t.references :page, null: false, foreign_key: true
      t.integer :block_type, null: false
      t.integer :position, null: false, default: 0

      # Structural criteria for a post_list block (`content_type`, `tag`,
      # `limit`). Deliberately *not* a Mobility attribute: these are query
      # parameters, identical in every locale.
      t.jsonb :settings, null: false, default: {}

      # A jsonb column holding one caption per locale, the shape Task 1 settled
      # on for translated plain text -- see ConvertPostTranslatedColumnsToJsonb.
      # (`body`, being rich text, lives in `action_text_rich_texts` instead.)
      t.jsonb :caption, null: false, default: {}

      t.timestamps
    end

    # Blocks are always read as an ordered list within one page, which is the
    # index this serves; `t.references` already covers page_id on its own.
    add_index :content_blocks, [ :page_id, :position ]
  end
end
