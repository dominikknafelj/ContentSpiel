# The site's default keeping time for a form's submissions (plan decision 4):
# a form whose `keep_days` is nil follows it at every run of the clean-up.
class AddFormKeepDaysToSiteSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :site_settings, :form_keep_days, :integer, null: false, default: 90
  end
end
