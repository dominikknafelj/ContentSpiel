# db/migrate/20261011120000_create_published_versions.rb
# What the public site shows of a page or post (drafts spec §4.1): one row per
# publish, never updated. `snapshot` holds the record's own fields and a
# post's tags, `blocks` a page's blocks, `lists_posts` whether any of them
# lists posts (so `PublicSite::Paths` loads only the copies that matter) and
# `tag_ids` a post's tags for list queries. No foreign key to the record: it
# is polymorphic, and `Publishable` deletes a destroyed record's copies.
class CreatePublishedVersions < ActiveRecord::Migration[8.1]
  def up
    create_table :published_versions do |t|
      t.string :record_type, null: false
      t.bigint :record_id, null: false
      t.integer :number, null: false
      t.jsonb :snapshot, null: false, default: {}
      t.jsonb :blocks, null: false, default: []
      t.boolean :lists_posts, null: false, default: false
      t.integer :tag_ids, array: true, null: false, default: []
      t.datetime :live_at, null: false
      t.references :created_by, index: false, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :created_at, null: false

      t.index %i[record_type record_id number], unique: true, name: "index_published_versions_on_record_and_number"
      t.index %i[record_type record_id live_at], name: "index_published_versions_on_record_and_live_at"
      t.index :tag_ids, using: :gin
    end

    # The first copy of everything already published or scheduled, from its
    # rows as they are, so the site is unchanged on the day this ships.
    Publishing::Version.reset_column_information
    Publishing::Version.take_first_copies!
  end

  def down
    drop_table :published_versions
  end
end
