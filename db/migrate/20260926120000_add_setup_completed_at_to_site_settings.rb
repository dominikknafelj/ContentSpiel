class AddSetupCompletedAtToSiteSettings < ActiveRecord::Migration[8.1]
  def up
    add_column :site_settings, :setup_completed_at, :datetime
    backfill
  end

  def down
    remove_column :site_settings, :setup_completed_at
  end

  # Any install that already has a user was set up before the wizard existed
  # and must never be redirected into it. Raw SQL, not models, so this
  # migration keeps working however SiteSetting changes later. The INSERT
  # covers installs where SiteSetting.instance never ran, so no row exists.
  def backfill
    execute <<~SQL
      UPDATE site_settings SET setup_completed_at = NOW()
      WHERE setup_completed_at IS NULL AND EXISTS (SELECT 1 FROM users)
    SQL
    execute <<~SQL
      INSERT INTO site_settings (title, default_locale, social_links, setup_completed_at, created_at, updated_at)
      SELECT 'My Site', 'en', '{}'::jsonb, NOW(), NOW(), NOW()
      WHERE EXISTS (SELECT 1 FROM users) AND NOT EXISTS (SELECT 1 FROM site_settings)
    SQL
  end
end
