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
  #
  # `title` became a translated jsonb column later
  # (`20261002110000_translate_site_title_and_tagline`), and this backfill is
  # also run directly against today's schema (test/models/setup_test.rb), so
  # the literal is spelled for whichever type the column has.
  def backfill
    title_type = connection.columns(:site_settings).find { |column| column.name == "title" }&.type
    title = title_type == :jsonb ? %q('{"en": "My Site"}'::jsonb) : "'My Site'"

    execute <<~SQL
      UPDATE site_settings SET setup_completed_at = NOW()
      WHERE setup_completed_at IS NULL AND EXISTS (SELECT 1 FROM users)
    SQL
    execute <<~SQL
      INSERT INTO site_settings (title, default_locale, social_links, setup_completed_at, created_at, updated_at)
      SELECT #{title}, 'en', '{}'::jsonb, NOW(), NOW(), NOW()
      WHERE EXISTS (SELECT 1 FROM users) AND NOT EXISTS (SELECT 1 FROM site_settings)
    SQL
  end
end
