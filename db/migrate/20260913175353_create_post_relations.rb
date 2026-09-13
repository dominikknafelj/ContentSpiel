class CreatePostRelations < ActiveRecord::Migration[8.1]
  def change
    create_table :post_relations do |t|
      t.references :post, null: false, foreign_key: { to_table: :posts }
      t.references :related_post, null: false, foreign_key: { to_table: :posts }

      t.timestamps
    end

    add_index :post_relations, [ :post_id, :related_post_id ], unique: true
  end
end
