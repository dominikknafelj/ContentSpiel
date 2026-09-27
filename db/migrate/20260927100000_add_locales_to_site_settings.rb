class AddLocalesToSiteSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :site_settings, :locales, :jsonb, null: false,
      default: [ { "code" => "en" }, { "code" => "de" }, { "code" => "es" } ]
  end
end
