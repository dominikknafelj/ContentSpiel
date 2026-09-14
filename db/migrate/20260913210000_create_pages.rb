# Pages are the site's navigation tree. Every translated attribute is a jsonb
# column holding one value per locale (`pages.title = {"en" => "About", "de" =>
# "Ueber uns"}`), the same shape Task 1 settled on for posts -- see
# ConvertPostTranslatedColumnsToJsonb.
class CreatePages < ActiveRecord::Migration[8.1]
  TRANSLATED_COLUMNS = %i[title slug subtitle meta_title meta_description].freeze

  # Hardcoded rather than read from I18n: a migration is a historical snapshot
  # and must not change meaning when the site adds a locale later.
  LOCALES = %w[en de es].freeze

  def change
    create_table :pages do |t|
      t.integer :page_type, null: false, default: 0

      TRANSLATED_COLUMNS.each do |column|
        t.jsonb column, null: false, default: {}
      end

      t.datetime :published_at

      # closure_tree reads and writes both of these: `parent_id` is the edge it
      # rebuilds the hierarchy table from, `position` is the sibling ordering
      # column it renumbers itself (`numeric_order: true`).
      t.references :parent, foreign_key: { to_table: :pages }, index: true
      t.integer :position

      t.timestamps
    end

    # Siblings may not share a slug. A unique index straight across the jsonb
    # `slug` column would compare whole translation hashes instead, which would
    # let two siblings both answer to "about" in English as long as one of them
    # also had a German slug. One partial expression index per locale states
    # the real rule, ignoring locales a page has no slug for.
    #
    # `nulls_not_distinct` is what makes this bite for root-level pages:
    # Postgres treats NULLs as distinct by default, so without it two pages
    # with `parent_id IS NULL` would never collide.
    LOCALES.each do |locale|
      add_index :pages, "parent_id, (slug ->> '#{locale}')",
        unique: true,
        nulls_not_distinct: true,
        where: "(slug ->> '#{locale}') IS NOT NULL",
        name: "index_pages_on_parent_id_and_slug_#{locale}"
    end
  end
end
