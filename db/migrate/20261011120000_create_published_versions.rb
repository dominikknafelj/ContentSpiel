# What the public site shows of a page or post (drafts spec §4.1): one row per
# publish, never updated. `snapshot` holds the record's own fields and a
# post's tags, `blocks` a page's blocks, `lists_posts` whether any of them
# lists posts (so `PublicSite::Paths` loads only the copies that matter) and
# `tag_ids` a post's tags for list queries. No foreign key to the record: it
# is polymorphic, and `Publishable` deletes a destroyed record's copies.
#
# THE FIRST COPIES ARE MADE BY LOGIC FROZEN IN THIS FILE: its own minimal
# models on the tables as they are at this version, calling no application
# class, so the migration means the same on any day it runs, whatever
# `Publishing::Version.take!` has grown to do since (it later writes columns
# that later migrations add). It builds the snapshot in the shape
# `Publishing::Snapshot.of` has today; `test/models/publishing/
# first_copies_migration_test.rb` compares the two while both exist. When the
# shape of a copy changes on purpose, that test says so and the change needs a
# SUCCESSOR migration: this one is never edited to follow.
class CreatePublishedVersions < ActiveRecord::Migration[8.1]
  class Row < ActiveRecord::Base
    self.abstract_class = true
    self.inheritance_column = nil
  end

  class MigrationPage < Row
    self.table_name = "pages"
    PAGE_TYPES = { 0 => "standard", 1 => "landing" }.freeze
  end

  class MigrationPost < Row
    self.table_name = "posts"
  end

  class MigrationBlock < Row
    self.table_name = "content_blocks"
  end

  class MigrationTag < Row
    self.table_name = "tags"
  end

  class MigrationPostTag < Row
    self.table_name = "post_tags"
  end

  class MigrationVersion < Row
    self.table_name = "published_versions"
  end

  PAGE_FIELDS = %w[title subtitle meta_title meta_description hero_alt hero_media_asset_id page_type translation_sources translation_original_changed_at].freeze
  POST_FIELDS = %w[title excerpt body metadata translated_metadata translation_sources translation_original_changed_at].freeze
  BLOCK_FIELDS = %w[id alt block_type caption created_at owner_id owner_type position settings translated_settings updated_at body
                    media_asset_id translation_sources translation_original_changed_at section_id section_column].freeze

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
    take_first_copies
  end

  def down
    drop_table :published_versions
  end

  # Public so that the test can run it. Idempotent: a record with a copy is
  # left alone. Answers how many it took.
  def take_first_copies
    [ [ MigrationPage, "Page" ], [ MigrationPost, "Post" ] ].sum do |model, type|
      [ model, MigrationVersion ].each(&:reset_column_information)
      missing = model.where.not(published_at: nil).where.not(id: MigrationVersion.where(record_type: type).select(:record_id))
      missing.find_each.count { |record| model.transaction { first_copy(type, record) } }
    end
  end

  private

  def first_copy(type, record)
    now = Time.current
    data = type == "Page" ? page_data(record) : post_data(record)
    MigrationVersion.create!(record_type: type, record_id: record.id, number: 1, live_at: now, created_at: now,
      snapshot: data.except("blocks"), blocks: data.fetch("blocks", []), lists_posts: data.fetch("blocks", []).any? { |block| block["block_type"] == "post_list" },
      tag_ids: data.fetch("tags", []).map { |tag| tag["id"] }.sort)
  end

  def page_data(page)
    fields = page.attributes.slice(*PAGE_FIELDS)
    fields["page_type"] = MigrationPage::PAGE_TYPES.fetch(fields["page_type"], fields["page_type"])
    { "fields" => fields.as_json, "blocks" => blocks_of(page) }
  end

  def post_data(post)
    tags = MigrationTag.where(id: MigrationPostTag.where(post_id: post.id).select(:tag_id)).order(:id).pluck(:id, :name)
    { "fields" => post.attributes.slice(*POST_FIELDS).as_json, "tags" => tags.map { |id, name| { "id" => id, "name" => name } } }
  end

  # Reading order: the top-level blocks by position, and after a section its
  # blocks column by column, each by position.
  def blocks_of(page)
    blocks = MigrationBlock.where(owner_type: "Page", owner_id: page.id).to_a
    inside = blocks.select(&:section_id).sort_by { |block| [ block.section_column.to_i, block.position, block.id ] }.group_by(&:section_id)
    blocks.reject(&:section_id).sort_by { |block| [ block.position, block.id ] }.flat_map { |block| [ block, *inside.fetch(block.id, []) ] }.map do |block|
      attributes = block.attributes.slice(*BLOCK_FIELDS).as_json
      attributes["listed_tag_id"] = listed_tag_id(block) if block.block_type == "post_list"
      attributes
    end
  end

  # The lowest id of the tag whose name is the filter's, whatever the case.
  def listed_tag_id(block)
    name = block.settings.to_h["tag"].to_s.strip
    return nil if name.empty?

    MigrationTag.where(MigrationTag.arel_table[:name].lower.eq(name.downcase)).order(:id).pick(:id)
  end
end
