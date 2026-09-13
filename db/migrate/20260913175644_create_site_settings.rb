class CreateSiteSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :site_settings do |t|
      t.string :title, null: false
      t.string :tagline
      t.jsonb :social_links, null: false, default: {}
      t.string :default_locale, null: false, default: "en"

      t.timestamps
    end
  end
end
