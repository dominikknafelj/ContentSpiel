module Trash
  # Daily (config/recurring.yml): permanently deletes what's been in the
  # trash longer than `SiteSetting#trash_retention_days` (trash spec §4.4);
  # 0 means never. A page branch goes by its root's `trashed_at` -- the
  # moment an editor trashed it -- since `Trash.roots` lists roots only.
  #
  # Runs as the trusted nil actor on the `:system` channel, so its
  # `*.purged` events read "System" in the audit log and `Trash::Purge`'s
  # authorization passes the way it does for any trusted code path. Each item
  # purges in its own savepoint (`Trash::Purge`); one that can't go is logged
  # and skipped, so a single stuck item (still in use, a mid-restore race)
  # never stops the rest of the sweep.
  #
  # Goes through `Trash.each_root(trashed_before:)`, not a plain
  # `relation.where(...).find_each` of its own: a page trashed on its own
  # (its own root) can be *older* than an ancestor trashed later, and both
  # can be past the cutoff -- `find_each` orders by id and would load that
  # page before the ancestor's branch purge runs, then hand `Purge` a
  # stale, already-destroyed record. `each_root` re-finds each root at its
  # turn and skips it if it's already gone, which is exactly what keeps
  # that stale record from producing a second, bogus `page.purged` event.
  class PurgeExpiredJob < ApplicationJob
    queue_as :default

    def perform
      days = SiteSetting.instance.trash_retention_days
      return if days.zero?

      Current.set(actor: nil, channel: :system) do
        Trash.each_root(trashed_before: days.days.ago) do |record|
          result = Purge.call(record, actor: nil)
          Rails.logger.info("[trash] kept #{record.class.name}##{record.id}: #{result.errors.to_sentence}") unless result.ok?
        end
      end
    end
  end
end
