module Media
  # `Media::RenditionJob` as the backfill queues it: one per image at a time.
  # A second enqueue of an image while its backfill job waits or runs is
  # discarded by Solid Queue (the semaphore is taken when the job becomes
  # ready and released when it finishes; a retry is scheduled with a wait, so
  # it becomes ready after the attempt that failed has released it). The
  # semaphore lapses after an hour, so a job lost with its worker does not
  # keep the image from the backfill for ever.
  #
  # Uploads and Regenerate images (`Media::Regenerate`, also `media:regenerate`)
  # queue the plain `Media::RenditionJob`, which no limit drops and which runs
  # before this one (priority 0 against this class's 10): a regenerate pressed while an older job runs under
  # the old settings must still be made.
  class BackfillRenditionJob < RenditionJob
    # Solid Queue runs the smaller number first: an upload's widths and a
    # Regenerate's (the plain job, priority 0) never wait behind the backfill.
    queue_with_priority 10

    limits_concurrency key: ->(asset) { asset }, to: 1, duration: 1.hour, on_conflict: :discard
  end
end
