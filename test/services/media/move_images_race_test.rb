require "test_helper"

# A move of a folder's images into its subfolder and the delete of that
# folder, on two connections at once. The delete re-parents the subfolder
# after it has updated the folder's images, which the move may be holding; a
# move that held the subfolder's row `FOR SHARE` would block that re-parent
# while waiting for the images, a deadlock (`ActiveRecord::Deadlocked`). Its
# `FOR KEY SHARE` blocks only a delete of the subfolder. Two connections need
# rows the other can see, so this class runs outside the test transaction (as
# `Media::DeleteFolderRaceTest`) and removes its rows, blobs included, in
# `clean`. `Audit.record` is replaced: the log is append-only.
class Media::MoveImagesRaceTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    clean
    @audit = Audit.method(:record)
    Audit.define_singleton_method(:record) { |*, **| nil }
  end

  teardown do
    Audit.define_singleton_method(:record, @audit) if @audit
    clean
    Current.reset
  end

  def clean
    Media::Asset.find_each { |asset| asset.file.purge } # the blob goes too: a leftover one is listed by media:orphans
    Media::Asset.find_each(&:destroy!)
    Media::Folder.where.not(parent_id: nil).delete_all # version: none (a test's own rows)
    Media::Folder.delete_all # version: none (a test's own rows)
  end

  def await_blocked(count)
    sql = "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND wait_event_type = 'Lock'"
    200.times do
      return if Thread.new { ActiveRecord::Base.connection_pool.with_connection { ActiveRecord::Base.connection.select_value(sql).to_i >= count } }.value

      sleep 0.025 # sleep: polling Postgres for the writers to be waiting on the image rows
    end
    flunk "#{count} writer(s) never blocked"
  end

  def in_thread(&work)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Current.reset
        as_owner(&work)
      end
    end
  end

  # The images are held by this thread's transaction while the two writers
  # queue in `order`, then released; whichever order they queued in, both
  # finish and every image sits in the subfolder.
  def race(order)
    parent = Media::Folder.create!(name: "Clients")
    inner = Media::Folder.create!(name: "Italy", parent_id: parent.id)
    assets = Array.new(2) { create_media_asset.tap { |asset| asset.update_column(:folder_id, parent.id) } } # version: none (a test's own rows)
    writers = { move: -> { Media::MoveImages.call(asset_ids: assets.map(&:id), folder: inner) }, delete: -> { Media::DeleteFolder.call(parent) } }
    threads = {}

    Media::Asset.transaction do
      Media::Asset.where(id: assets.map(&:id)).order(:id).lock("FOR UPDATE").to_a
      order.each_with_index do |name, index|
        threads[name] = in_thread { writers.fetch(name).call }
        await_blocked(index + 1)
      end
    end
    results = threads.transform_values(&:value)

    results.each { |name, result| assert result.ok?, "#{name}: #{result.errors.inspect}" }
    assert_equal [ inner.id ] * 2, assets.map { |asset| asset.reload.folder_id }
    assert_not Media::Folder.exists?(parent.id)
    assert_nil inner.reload.parent_id
  ensure
    threads.each_value(&:join)
  end

  test "a move into a subfolder queued behind a delete of its parent finishes with no deadlock" do
    race(%i[delete move])
  end

  test "a delete of the parent queued behind a move into the subfolder finishes with no deadlock" do
    race(%i[move delete])
  end
end
