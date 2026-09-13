class CreatePosts < ActiveRecord::Migration[8.1]
  def change
    create_table :posts do |t|
      t.integer :content_type, null: false, default: 0
      t.string :title, null: false
      t.string :slug, null: false
      t.string :excerpt
      t.datetime :published_at
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :posts, [ :content_type, :slug ], unique: true
  end
end
