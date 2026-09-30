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
  class PurgeExpiredJob < ApplicationJob
    queue_as :default

    def perform
      days = SiteSetting.instance.trash_retention_days
      return if days.zero?

      cutoff = days.days.ago
      Current.set(actor: nil, channel: :system) do
        Trash.roots.each_value do |relation|
          relation.where(trashed_at: ...cutoff).find_each do |record|
            result = Purge.call(record, actor: nil)
            Rails.logger.info("[trash] kept #{record.class.name}##{record.id}: #{result.errors.to_sentence}") unless result.ok?
          end
        end
      end
    end
  end
end
