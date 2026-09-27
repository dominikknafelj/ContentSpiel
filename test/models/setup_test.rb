require "test_helper"
require Rails.root.join("db/migrate/20260926120000_add_setup_completed_at_to_site_settings")

class SetupTest < ActiveSupport::TestCase
  test "setup is not required once completed" do
    assert_not Setup.required?
  end

  test "setup is required while no settings row is completed" do
    site_settings(:default).update!(setup_completed_at: nil)

    assert Setup.required?
  end

  test "setup is required on an empty database" do
    SiteSetting.delete_all

    assert Setup.required?
  end

  test "the backfill completes setup for an existing install with users" do
    site_settings(:default).update!(setup_completed_at: nil)

    run_backfill

    assert_not Setup.required?
  end

  # SiteSetting.instance creates its row lazily, so an existing install can
  # have users but no site_settings row at all.
  test "the backfill creates a completed row when users exist but settings don't" do
    SiteSetting.delete_all

    run_backfill

    assert_not Setup.required?
    assert_equal 1, SiteSetting.count
  end

  test "the backfill leaves a fresh install (no users) in setup" do
    SiteSetting.delete_all
    User.destroy_all

    run_backfill

    assert Setup.required?
  end

  test "complete! creates the homepage and ends setup" do
    site_settings(:default).update!(setup_completed_at: nil)

    Setup.complete!

    assert_not Setup.required?
    assert Page.exists?(parent_id: nil)
  end

  test "complete! is idempotent" do
    site_settings(:default).update!(setup_completed_at: nil)
    Setup.complete!

    assert_no_difference "Page.count" do
      Setup.complete!
    end
  end

  test "required? stops querying once setup is complete and resets when it is undone" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    assert_not Setup.required?
    assert_no_queries { assert_not Setup.required? }

    site_settings(:default).update!(setup_completed_at: nil)
    assert Setup.required?
  end

  private
    def run_backfill
      ActiveRecord::Migration.suppress_messages { AddSetupCompletedAtToSiteSettings.new.backfill }
    end
end
