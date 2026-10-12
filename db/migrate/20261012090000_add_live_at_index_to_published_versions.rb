# The public content version reads the newest `live_at` among the copies in
# force (`PublicSite.content_version`): a change scheduled for later moves the
# version when its time passes, with no write. That is `MAX(live_at) WHERE
# live_at <= now()` over the whole table, on every public request that has to
# know the version, so it is one index lookup rather than a scan of a table
# that holds a copy of every publish. (The existing partial index holds only
# the copies not yet settled.)
class AddLiveAtIndexToPublishedVersions < ActiveRecord::Migration[8.1]
  def change
    add_index :published_versions, :live_at, name: "index_published_versions_on_live_at"
  end
end
