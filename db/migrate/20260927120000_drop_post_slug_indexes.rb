class DropPostSlugIndexes < ActiveRecord::Migration[8.1]
  def change
    remove_index :posts, name: "index_posts_on_content_type_and_slug_de"
    remove_index :posts, name: "index_posts_on_content_type_and_slug_en"
    remove_index :posts, name: "index_posts_on_content_type_and_slug_es"
  end
end
