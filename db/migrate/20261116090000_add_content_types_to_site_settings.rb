# The post types a site has switched on (docs/reference/content-blocks-and-types.md).
# A new site starts with Blog alone (the column's default); a site that exists
# keeps all three built-in types on, since its posts of those types are live.
class AddContentTypesToSiteSettings < ActiveRecord::Migration[8.1]
  def up
    add_column :site_settings, :content_types, :jsonb, default: [ "blog" ], null: false

    Class.new(ActiveRecord::Base) { self.table_name = "site_settings" }
      .update_all(content_types: %w[blog resume_entry now_update])
  end

  def down
    remove_column :site_settings, :content_types
  end
end
