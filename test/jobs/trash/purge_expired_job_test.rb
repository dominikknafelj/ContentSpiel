require "test_helper"

class Trash::PurgeExpiredJobTest < ActiveJob::TestCase
  setup do
    Current.actor = users(:one)
    @old = create_post(title: "Old")
    @fresh = create_post(title: "Fresh")
    [ @old, @fresh ].each { |p| Trash::Move.call(p) }
    Current.reset
  end

  test "purges items trashed longer ago than the retention period" do
    @old.update_columns(trashed_at: 31.days.ago)
    @fresh.update_columns(trashed_at: 29.days.ago)
    Trash::PurgeExpiredJob.perform_now

    assert_not Post.exists?(@old.id)
    assert Post.exists?(@fresh.id)
    event = Audit::Event.where(action: "post.purged", subject_id: @old.id).last
    assert_nil event.actor_id
    assert_equal "system", event.channel
  end

  test "0 days turns it off" do
    site_settings(:default).update!(trash_retention_days: 0)
    @old.update_columns(trashed_at: 400.days.ago)
    Trash::PurgeExpiredJob.perform_now
    assert Post.exists?(@old.id)
  end

  test "a branch goes by its root's date" do
    Current.actor = users(:one)
    parent = create_page(title: "Section")
    child = create_page(title: "Child", parent: parent)
    Trash::Move.call(parent)
    Current.reset
    parent.update_columns(trashed_at: 31.days.ago)
    child.update_columns(trashed_at: 1.day.ago)   # descendants carry the root's date in practice; the root decides
    Trash::PurgeExpiredJob.perform_now
    assert_not Page.exists?(child.id)
  end

  test "an item that can't be purged doesn't stop the run" do
    stuck = create_media_asset
    keeper = create_page(title: "Keeper")
    Current.set(actor: users(:one)) { Pages::Save.call(keeper, attributes: { hero_media_asset_id: stuck.id }) }
    stuck.update_columns(trashed_at: 40.days.ago)
    @old.update_columns(trashed_at: 31.days.ago)

    Trash::PurgeExpiredJob.perform_now
    assert Media::Asset.exists?(stuck.id)
    assert_not Post.exists?(@old.id)
  end

  test "is scheduled daily in every environment" do
    config = YAML.load_file(Rails.root.join("config/recurring.yml"), aliases: true)
    %w[production development test].each do |env|
      assert_equal "Trash::PurgeExpiredJob", config.dig(env, "trash_purge_expired", "class"), env
    end
  end
end
