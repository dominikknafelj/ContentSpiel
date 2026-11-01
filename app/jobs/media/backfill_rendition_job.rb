module Media
  # `Media::RenditionJob` as the backfill queues it: one per image at a time.
  # A second enqueue of an image while its backfill job waits or runs is
  # discarded by Solid Queue (the semaphore is taken when the job becomes
  # ready and released when it finishes; a retry is scheduled with a wait, so
  # it becomes ready after the attempt that failed has released it). The
  # semaphore lapses after an hour, so a job lost with its worker does not
  # keep the image from the backfill for ever.
  #
  # Uploads and `media:regenerate` queue the plain `Media::RenditionJob`,
  # which no limit drops: a regenerate pressed while an older job runs under
  # the old settings must still be made.
  class BackfillRenditionJob < RenditionJob
    limits_concurrency key: ->(asset) { asset }, to: 1, duration: 1.hour, on_conflict: :discard
  end
end
