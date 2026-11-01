module Media
  # Queues the widths of every image that is due (`Media::Asset.backfill_due`)
  # and nothing else. Those are images with no preview or no size yet, rows
  # from before the decode at upload, and images still serving the adopted
  # widths, which carry camera data. The rendition job makes what is missing,
  # and an image it cannot read is recorded as failed and never asked again.
  # It runs every ten minutes (`config/recurring.yml`), so the images of an
  # existing site are made after the deploy without a migration enqueuing
  # into the queue's database. On a site with nothing due it is one
  # `exists?`, answered by a partial index.
  #
  # Bounded twice, so a large library never floods the one-thread images
  # queue in front of new uploads:
  # - a run queues BATCH images at most, the oldest first (about what the
  #   queue makes in ten minutes);
  # - it queues `Media::BackfillRenditionJob`, which Solid Queue holds to one
  #   per image at a time and discards beyond that, so an image whose job is
  #   still waiting from the run before is not queued again.
  # The selection still reads what is made, never what is queued.
  class BackfillJob < ApplicationJob
    BATCH = 300

    queue_as :images

    def perform(limit: BATCH)
      due = Media::Asset.backfill_due
      return unless due.exists?

      due.order(:id).limit(limit).each { |asset| Media::BackfillRenditionJob.perform_later(asset) }
    end
  end
end
