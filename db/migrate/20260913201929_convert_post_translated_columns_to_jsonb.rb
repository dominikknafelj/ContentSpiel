# Mobility's :jsonb backend stores every locale's value for an attribute in a
# single jsonb column named after that attribute, e.g.
# `posts.title = {"en" => "Hello", "de" => "Hallo"}`.
class ConvertPostTranslatedColumnsToJsonb < ActiveRecord::Migration[8.1]
  TRANSLATED_COLUMNS = %i[title slug excerpt].freeze

  # Locales are hardcoded rather than read from I18n: a migration is a
  # historical snapshot, and must not change meaning when the site adds a
  # locale later.
  LOCALES = %w[en de es].freeze

  def up
    TRANSLATED_COLUMNS.each do |column|
      # Whatever is in the column today is English -- it was written before
      # there was any notion of a locale.
      change_column :posts, column, :jsonb, default: {}, null: false,
        using: "CASE WHEN #{column} IS NULL OR #{column} = '' " \
               "THEN '{}'::jsonb ELSE jsonb_build_object('en', #{column}) END"
    end

    # A unique index straight across the jsonb `slug` column would compare
    # whole translation hashes, which is not the constraint we want: it would
    # let two blog posts both use "hello-world" in English as long as one of
    # them also had a German slug. One partial expression index per locale
    # states the real rule -- unique per content_type, per locale, ignoring
    # locales a post has no slug for.
    remove_index :posts, column: %i[content_type slug],
      name: :index_posts_on_content_type_and_slug, unique: true

    LOCALES.each do |locale|
      add_index :posts, "content_type, (slug ->> '#{locale}')",
        unique: true,
        where: "(slug ->> '#{locale}') IS NOT NULL",
        name: "index_posts_on_content_type_and_slug_#{locale}"
    end
  end

  def down
    LOCALES.each do |locale|
      remove_index :posts, name: "index_posts_on_content_type_and_slug_#{locale}"
    end

    TRANSLATED_COLUMNS.each do |column|
      change_column :posts, column, :string, default: nil, null: true,
        using: "#{column} ->> 'en'"
    end

    change_column_null :posts, :title, false
    change_column_null :posts, :slug, false

    add_index :posts, %i[content_type slug], unique: true,
      name: :index_posts_on_content_type_and_slug
  end
end
