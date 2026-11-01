# Image delivery's settings (the site's choice of format, quality, widths and
# largest upload). The defaults are what a site that changed nothing gets:
# WebP at 75 and AVIF at 50 are libvips' own defaults. `ImageSettings` is the
# one reader; the bounds are validated on `SiteSetting`.
class AddImagesToSiteSettings < ActiveRecord::Migration[8.1]
  def change
    change_table :site_settings, bulk: true do |t|
      t.string :image_format, null: false, default: "webp"
      t.integer :image_quality_webp, null: false, default: 75
      t.integer :image_quality_avif, null: false, default: 50
      t.jsonb :image_widths, null: false, default: [ 480, 960, 1600, 2400 ]
      t.integer :image_max_upload_mb, null: false, default: 10
    end
  end
end
