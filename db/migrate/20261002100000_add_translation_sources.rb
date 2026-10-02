# Translation helpers spec §3.1: per field and locale, the digest of the
# primary-language value a translation was last saved against.
class AddTranslationSources < ActiveRecord::Migration[8.1]
  def change
    %i[pages posts content_blocks media_assets site_settings].each do |table|
      add_column table, :translation_sources, :jsonb, null: false, default: {}
    end
  end
end
