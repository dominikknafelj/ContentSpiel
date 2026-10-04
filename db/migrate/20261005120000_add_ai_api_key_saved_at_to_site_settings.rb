# When the AI key was last saved (decision D11), so Settings can say "Key saved
# · added 2 Oct". Nullable: a key stored before this column has no date and
# reads "Key saved" alone. Written beside the key by `Settings::Save#write_ai_key`.
class AddAiApiKeySavedAtToSiteSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :site_settings, :ai_api_key_saved_at, :datetime
  end
end
