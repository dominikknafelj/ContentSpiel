# There is only ever one SiteSetting (singleton), so the Settings menu entry
# skips the one-row index and opens its edit form directly.
class Avo::SiteSettingsController < Avo::ResourcesController
  def index
    redirect_to avo.edit_resources_site_setting_path(Current.site)
  end
end
