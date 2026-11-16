require "test_helper"

# A move into a folder and the folder's delete on two connections at once: a
# move holds the folder's row `FOR SHARE`, the delete takes it `FOR UPDATE`
# after the tree's lock, so the delete waits for the move's commit and carries
# the moved image up with the rest instead of leaving it to the foreign key's
# nullify. Two connections need rows the other can see, so this class runs
# outside the test transaction (as `Settings::SwitchRaceTest`) and removes
# its rows in `clean`. `Audit.record` is replaced: the log is append-only.
class Media::DeleteFolderRaceTest < ActiveSupport::TestCase
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

  def await_blocked(waiting)
    sql = "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND wait_event_type = 'Lock' AND query LIKE #{ActiveRecord::Base.connection.quote(waiting)}"
    200.times do
      return if Thread.new { ActiveRecord::Base.connection_pool.with_connection { ActiveRecord::Base.connection.select_value(sql).to_i.positive? } }.value

      sleep 0.025 # sleep: polling Postgres for the delete to be waiting on the move's row lock
    end
    flunk "the delete never blocked behind the move"
  end

  test "a delete waits for a move into the folder and moves those images up too" do
    parent = Media::Folder.create!(name: "Clients")
    doomed = Media::Folder.create!(name: "Old", parent_id: parent.id)
    asset = create_media_asset
    thread = nil

    Media::Folder.transaction do
      Media::Folder.lock("FOR SHARE").find(doomed.id)
      asset.update_column(:folder_id, doomed.id) # version: none (a test's own rows)
      thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Current.reset
          as_owner { Media::DeleteFolder.call(doomed) }
        end
      end
      await_blocked("%media_folders%FOR UPDATE%")
    end
    result = thread.value

    assert result.ok?, result.errors.inspect
    assert_equal parent.id, asset.reload.folder_id
    assert_not Media::Folder.exists?(doomed.id)
  ensure
    thread&.join
  end
end
