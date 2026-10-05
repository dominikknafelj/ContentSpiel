# Technical cleanup spec §4.9. `published_at` on pages and posts is what
# `PublicSite.content_version`'s two "newest publication time that has
# passed" lookups read (an index scan from the top instead of a pass over the
# table), and what every `published` scope filters by; `updated_at` serves
# the lists ordered by it (the dashboard, the posts list); `block_type`
# serves `ContentBlock.listing`, which every URL sync of a post starts from.
class AddPublicationIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :pages, :published_at
    add_index :posts, :published_at
    add_index :pages, :updated_at
    add_index :posts, :updated_at
    add_index :content_blocks, :block_type
  end
end
