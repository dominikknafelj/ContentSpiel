# A new site starts with English alone (issue #142): the default was the
# owner's own three languages, and a site that wanted one began with every
# page marked as needing translation twice. Only the column's default
# changes; a site that exists keeps the languages it has.
class DefaultSiteLocalesToEnglish < ActiveRecord::Migration[8.1]
  def change
    change_column_default :site_settings, :locales,
      from: [ { "code" => "en" }, { "code" => "de" }, { "code" => "es" } ],
      to: [ { "code" => "en" } ]
  end
end
