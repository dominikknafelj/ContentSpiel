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

  # Trash spec §4.4: an exception out of one purge is logged, never the
  # end of the sweep.
  test "an item whose purge raises doesn't stop the run" do
    @old.update_columns(trashed_at: 31.days.ago)
    older = create_post(title: "Older")
    older.update_columns(trashed_at: 40.days.ago) # tried first: `Trash.roots` orders by trashed_at
    original = Trash::Purge.method(:call)

    with_singleton_override(Trash::Purge, :call, ->(record, **options) {
      raise ArgumentError, "boom" if record.id == older.id
      original.call(record, **options)
    }) { Trash::PurgeExpiredJob.perform_now }

    assert Post.exists?(older.id)
    assert_not Post.exists?(@old.id)
  end

  test "a page trashed alone, then swept up by its later-trashed ancestor's branch purge, isn't purged a second time" do
    Current.actor = users(:one)
    ancestor = create_page(title: "Ancestor")
    descendant = create_page(title: "Descendant", parent: ancestor)
    Trash::Move.call(descendant)
    Trash::Move.call(ancestor)
    Current.reset

    # Both past the 30-day cutoff, with the ancestor's own trashed_at set
    # older than the descendant's -- so the ancestor is the one a plain
    # id-ordered `find_each` (the bug: the ancestor is always created,
    # hence numbered, before its own descendant) and the properly ordered
    # `Trash.each_root` (the fix) both visit first, isolating the one
    # thing that actually differs between them: whether the descendant --
    # already swept away for good by the ancestor's own branch purge -- is
    # re-visited afterwards from a stale, pre-destroy copy.
    ancestor.update_columns(trashed_at: 40.days.ago)
    descendant.update_columns(trashed_at: 31.days.ago)

    Trash::PurgeExpiredJob.perform_now

    assert_not Page.exists?(ancestor.id)
    assert_not Page.exists?(descendant.id)
    # Exactly one event per page: the descendant's own, recorded by the
    # ancestor's branch purge (`purged_with`) -- never a second, bogus one
    # from a stale re-visit.
    assert_equal 1, Audit::Event.where(action: "page.purged", subject_id: ancestor.id).count
    assert_equal 1, Audit::Event.where(action: "page.purged", subject_id: descendant.id).count
    assert_equal "Page##{ancestor.id}", Audit::Event.find_by!(action: "page.purged", subject_id: descendant.id).metadata["purged_with"]
  end

  test "is scheduled daily in every environment" do
    config = YAML.load_file(Rails.root.join("config/recurring.yml"), aliases: true)
    %w[production development test].each do |env|
      assert_equal "Trash::PurgeExpiredJob", config.dig(env, "trash_purge_expired", "class"), env
    end
  end
end
