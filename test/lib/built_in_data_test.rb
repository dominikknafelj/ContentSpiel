require "test_helper"
require_relative "../support/schema_loaded_database"

# A migration that inserts rows gives them only to a database that RUNS it,
# and no new database does: `db:prepare`, `db:setup`, `db:schema:load`, and
# since Rails 8 `db:migrate` on an empty database, all load `db/schema.rb`,
# which carries tables and no rows. That is how the built-in groups went
# missing from every new site: `SeedAccessControlGroups` inserted them, the
# fixtures held them, and a first production start had none (the setup
# wizard's token step answered 404).
#
# So every migration that writes rows is named here with where a
# schema-loaded database gets the same from, or why it needs nothing:
#
# - `built_in:` rows every site needs. The value names what makes them on a
#   database no migration ran on, and the test below makes them that way on
#   an emptied database and compares.
# - `derived:` rows computed from rows that were there (a backfill). A
#   database with no content has nothing to compute.
# - `lazy:` a row the application makes itself the first time it is asked.
#
# A new migration that inserts rows fails "every migration that inserts rows
# is accounted for" until it has an entry, which is the moment to ask what a
# schema-loaded database gets instead (for a built-in row: add it to the
# block at the top of `db/seeds.rb`).
#
# WHAT THIS CANNOT SEE. It reads source, by the names below: a migration
# that writes rows through a method called something else (a model's own
# `backfill!`, a rake task it invokes) is not found, and neither is a row an
# `UPDATE` alone could not make. It takes a `derived:` and a `lazy:` reason
# at its word: only the `built_in:` entries are run. And it knows nothing of
# a row that never had a migration: a registry the code expects in a table.
class BuiltInDataTest < ActiveSupport::TestCase
  include SchemaLoadedDatabase

  INSERTS = /\bINSERT\s+INTO\b|\.(?:create|insert|insert_all|upsert|upsert_all|find_or_create_by|create_or_find_by|first_or_create|save)!?(?![\w?])|\bSeeds\.|\.rebuild\w*[!?]?|\.instance\b/i

  ACCOUNTED = {
    "20260926120000_add_setup_completed_at_to_site_settings" => { lazy: "the settings row of a site that already had users; a new site's is made by SiteSetting.instance at its first request, with setup pending" },
    "20260928060000_seed_access_control_groups" => { built_in: "Groups::EnsureBuiltIns" },
    "20260929050000_move_images_into_media_library" => { derived: "library images and usage rows for the attachments pages and blocks had" },
    "20260929060000_grant_media_manage_to_built_in_groups" => { built_in: "Groups::EnsureBuiltIns" },
    "20260929070000_backfill_rich_text_media_usages" => { derived: "usage rows for the images in bodies that existed" },
    "20260929090100_grant_trash_empty_to_admin" => { built_in: "Groups::EnsureBuiltIns" },
    "20261002120100_grant_ai_translate_to_built_in_groups" => { built_in: "Groups::EnsureBuiltIns" },
    "20261004110000_create_translation_states" => { derived: "translation states of the pages, posts and blocks that existed" },
    "20261005150000_create_public_site_versions" => { lazy: "the counter's row: no row reads as 0 and the first PublicSite.bump_version! upserts it" },
    "20261011120000_create_published_versions" => { derived: "a first copy of each page and post that was published" }
  }.freeze

  # What each `built_in:` migration gave a group, as it is written in the
  # migration: read by the comparison below, so "EnsureBuiltIns covers it"
  # is run and not only said.
  GRANTED_BY_MIGRATION = {
    "20260929060000_grant_media_manage_to_built_in_groups" => { "media.manage" => %w[Admin Editor] },
    "20260929090100_grant_trash_empty_to_admin" => { "trash.empty" => %w[Admin] },
    "20261002120100_grant_ai_translate_to_built_in_groups" => { "ai.translate" => %w[Admin Editor] }
  }.freeze

  def self.code(source) = source.lines.reject { |line| line.lstrip.start_with?("#") }.map { |line| line.sub(/\s#\s.*$/, "") }.join

  def self.inserting(sources) = sources.select { |_, source| code(source).match?(INSERTS) }.keys

  def migrations = Rails.root.glob("db/migrate/*.rb").sort.to_h { |file| [ file.basename(".rb").to_s, file.read ] }

  test "every migration that inserts rows is accounted for: built in, derived from rows that were there, or made when first asked" do
    unnamed = self.class.inserting(migrations) - ACCOUNTED.keys

    assert_empty unnamed, <<~MESSAGE
      These migrations insert rows, and a new database never runs a migration: it loads db/schema.rb.
      Add each to ACCOUNTED in #{__FILE__} with what a schema-loaded database gets instead. A row
      every site needs is made by the block at the top of db/seeds.rb (and named `built_in:` here).
    MESSAGE
  end

  test "every entry names a migration that still inserts rows, says one thing and gives its reason" do
    assert_empty ACCOUNTED.keys - self.class.inserting(migrations), "entries for migrations that are gone or insert nothing"

    ACCOUNTED.each do |name, entry|
      assert_equal 1, entry.size, name
      assert_includes %i[built_in derived lazy], entry.keys.first, name
      assert_operator entry.values.first.length, :>=, 20, "#{name} needs its reason" unless entry.key?(:built_in)
    end
    assert_equal GRANTED_BY_MIGRATION.keys.sort, ACCOUNTED.select { |_, entry| entry.key?(:built_in) }.keys.sort - [ "20260928060000_seed_access_control_groups" ]
  end

  test "the pattern finds an insert however it is written, and not a change of structure" do
    found = lambda { |source| self.class.inserting("m" => source).any? }

    assert found.call(%(execute "INSERT INTO things (id) VALUES (1)"))
    assert found.call("execute <<~SQL\n  insert into things (id) values (1)\nSQL")
    assert found.call("Thing.create!(name: 1)")
    assert found.call("group.grants.find_or_create_by!(permission: \"x\") { |grant| grant.scope = {} }")
    assert found.call("Thing.insert_all(rows)")
    assert found.call("Thing.upsert({ id: 1 })")
    assert found.call("thing.save!")
    assert found.call("AccessControl::Seeds.ensure_built_in_groups!")
    assert found.call("Translations::StateIndex.rebuild_all")
    assert_not found.call("create_table :things do |t|\n  t.string :name\nend\nadd_index :things, :name")
    assert_not found.call("# Thing.create!(name: 1)\nadd_column :things, :n, :integer # then Thing.insert_all(rows)")
    assert_not found.call(%(execute "UPDATE things SET n = 0"))
  end

  test "what the built-in migrations inserted, Groups::EnsureBuiltIns makes on a database no migration ran on" do
    named = ACCOUNTED.select { |_, entry| entry.key?(:built_in) }.values.map { |entry| entry[:built_in] }.uniq
    assert_equal [ "Groups::EnsureBuiltIns" ], named, "a new kind of built-in row needs its own comparison in this test"
    assert_includes Rails.root.join("db/seeds.rb").read.split("return unless Rails.env.development?").first, "Groups::EnsureBuiltIns.call",
      "the seed file makes the built-in rows above the line that ends it outside development"

    empty_as_after_a_schema_load
    Groups::EnsureBuiltIns.call
    made = groups_as_data

    GRANTED_BY_MIGRATION.each do |migration, grants|
      grants.each do |permission, groups|
        holders = made.select { |_, _, held| held.include?([ permission, {} ]) }.map(&:first)
        assert_equal groups.sort, holders.sort & %w[Admin Editor], "#{migration}: #{permission}"
      end
    end

    # The seeding migration's own step, on the same empty tables.
    AccessControl::Grant.delete_all
    AccessControl::Group.delete_all
    AccessControl::Seeds.ensure_built_in_groups!
    assert_equal groups_as_data, made
  end
end
