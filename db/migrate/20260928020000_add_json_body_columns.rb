# The per-locale Tiptap/ProseMirror JSON documents (design spec §3.1) that
# replace the ActionText bodies on `posts` and `content_blocks` --
# `{ locale => tiptap_doc }`, the same jsonb-per-locale shape every other
# translated column here already has, declared with `translates :body_doc`
# on the default jsonb backend.
#
# Named `body_doc`, not `body`, for now: the ActionText `body` (one
# `action_text_rich_texts` row per record/locale via mobility-actiontext)
# has to stay readable until Task 6's `rich_text:migrate_from_action_text`
# task has converted it. Task 6 then drops ActionText and renames this
# column to `body` -- so nothing outside the models' own `body_document`/
# `assign_body` seam should ever name `body_doc` directly.
#
# `change` is reversible as-is (`add_column` with a default), which is all
# the "migrations must be reversible" rule asks of a column add.
class AddJsonBodyColumns < ActiveRecord::Migration[8.1]
  def change
    add_column :posts, :body_doc, :jsonb, default: {}, null: false
    add_column :content_blocks, :body_doc, :jsonb, default: {}, null: false
  end
end
