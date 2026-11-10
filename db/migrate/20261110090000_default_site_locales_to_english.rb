# A new site starts with English alone: a site that wants one language would
# otherwise start with every page needing translation into languages nobody
# asked for. Only the column's default changes; a site that exists keeps the
# languages it has.
class DefaultSiteLocalesToEnglish < ActiveRecord::Migration[8.1]
  def change
    change_column_default :site_settings, :locales,
      from: [ { "code" => "en" }, { "code" => "de" }, { "code" => "es" } ],
      to: [ { "code" => "en" } ]
  end
end
