# The first half of retiring ActionText (tiptap design spec §5): the JSON
# document column takes over the `body` name the ActionText attribute used
# to have (`translates :body` on the jsonb backend, spec §3.1). Its own
# migration, separate from `DropActionText`, so that on an install with
# ActionText bodies still to convert `db:migrate` gets this far, stops at
# `DropActionText`'s guard, and `rich_text:migrate_from_action_text` then
# writes into the column the code already calls `body`.
#
# Nothing to lose: ActionText stored its bodies in `action_text_rich_texts`,
# never in a `posts.body`/`content_blocks.body` column, so the name is free.
class RenameBodyDocToBody < ActiveRecord::Migration[8.1]
  def change
    rename_column :posts, :body_doc, :body
    rename_column :content_blocks, :body_doc, :body
  end
end
