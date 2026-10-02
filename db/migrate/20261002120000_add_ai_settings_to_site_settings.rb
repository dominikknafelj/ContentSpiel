# The AI translation settings (translation helpers spec §6.2): which
# provider (`AI::Providers` name), which model (blank = `AI::DEFAULT_MODEL`)
# and the API key. `ai_api_key` is `text`, not `string`: it holds the
# Active Record encryption payload (`SiteSetting` `encrypts :ai_api_key`),
# a JSON envelope several times the length of the key itself.
class AddAiSettingsToSiteSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :site_settings, :ai_provider, :string
    add_column :site_settings, :ai_model, :string
    add_column :site_settings, :ai_api_key, :text
  end
end
