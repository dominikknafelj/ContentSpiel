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
    # `delete_all`, not `destroy_all` -- `User#ensure_not_last_owner` (Task
    # 8's `before_destroy`) would refuse to remove the second fixture user,
    # leaving this "no users" scenario with one.
    User.delete_all

    run_backfill

    assert Setup.required?
  end

  test "complete! ends setup" do
    site_settings(:default).update!(setup_completed_at: nil)

    Setup.complete!

    assert_not Setup.required?
  end

  test "complete! is idempotent" do
    site_settings(:default).update!(setup_completed_at: nil)
    Setup.complete!
    completed_at = site_settings(:default).reload.setup_completed_at

    Setup.complete!

    assert_equal completed_at, site_settings(:default).reload.setup_completed_at
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
