module Media
  # Queues `Media::RenditionJob` for every kept image that has no preview or
  # no size yet, rows from before the decode at upload, and nothing else: the
  # rendition job makes what is missing, and an image it cannot read is
  # recorded as failed and never asked again. It runs every ten minutes
  # (`config/recurring.yml`), so the images of an existing site get their
  # previews after the deploy without a migration enqueuing into the queue's
  # database. On a site with nothing missing it is one `exists?`, answered by
  # a partial index (`Media::Asset.missing_decode`).
  #
  # A run that finds an image still waiting in the queue from the run before
  # queues it again; the second job finds it decoded and made, and does
  # nothing.
  class BackfillJob < ApplicationJob
    queue_as :images

    def perform
      missing = Media::Asset.missing_decode
      return unless missing.exists?

      missing.find_each { |asset| Media::RenditionJob.perform_later(asset) }
    end
  end
end
