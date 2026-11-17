# How visitors' browsers get the theme's stylesheet (Settings → Page speed,
# `ThemeCss.inline_for?`): `automatic` (drawn into the page while it is at or
# under `ThemeCss::INLINE_LIMIT` compressed, linked over it), `inline` (always
# drawn in) or `file` (always linked). Every existing site keeps `automatic`,
# which is what every public page did before the setting existed.
class AddStylesheetModeToSiteSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :site_settings, :stylesheet_mode, :string, null: false, default: "automatic"
    add_check_constraint :site_settings, "stylesheet_mode::text = ANY (ARRAY['automatic'::text, 'inline'::text, 'file'::text])",
      name: "site_settings_stylesheet_mode_known"
  end
end
