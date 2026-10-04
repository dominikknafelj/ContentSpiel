# `{ field => ISO-8601 time }`: when the primary-language value of each
# tracked field last changed (`Translations::Tracker`), so the translations
# screen can say "original changed 3 days ago". Empty until a field's
# original is next edited -- records from before this column simply have no
# time, which every reader treats as "unknown".
class AddTranslationOriginalChangedAt < ActiveRecord::Migration[8.1]
  TABLES = %i[pages posts content_blocks media_assets site_settings].freeze

  def change
    TABLES.each do |table|
      add_column table, :translation_original_changed_at, :jsonb, default: {}, null: false
    end
  end
end
