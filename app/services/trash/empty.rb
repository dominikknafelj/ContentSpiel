module Trash
  # Empties the whole trash (trash spec §4.4), Admin only (`trash.empty`).
  # Each item goes through `Trash::Purge` in `Trash.roots` order (page
  # branches, then posts, then images, so an image's trashed owners are gone
  # by the time it's tried), each purge in its own savepoint, so one item
  # that can't go (an image something kept still uses) is skipped and
  # reported in `#skipped`, never aborting the rest. One `trash.emptied`
  # event summarises the run; every purge records its own `<kind>.purged`.
  #
  # No transaction around the whole run, on purpose: each purge commits (or
  # rolls back) on its own, and an image's file is only purged after its
  # own delete commits -- one long transaction would hold every file until
  # the very end and lose the lot on an unexpected error.
  class Empty < ApplicationService
    attr_reader :purged_count, :skipped

    def initialize(actor: Current.actor)
      @actor = actor
      @purged_count = 0
      @skipped = []
    end

    def call
      # `trash.empty` is an admin-area key: no subject, so a nil record.
      return denied("trash.empty", nil) unless authorize!("trash.empty", nil)

      Trash.each_root do |record|
        result = Purge.call(record, actor: @actor)
        if result.ok?
          @purged_count += 1
        else
          @skipped << { record:, errors: result.errors }
        end
      end
      record_event("trash.emptied", metadata: { purged: @purged_count, skipped: @skipped.size })

      success(nil)
    end
  end
end
