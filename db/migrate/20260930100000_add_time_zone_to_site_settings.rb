class AddTimeZoneToSiteSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :site_settings, :time_zone, :string, null: false, default: "UTC"
  end
end
