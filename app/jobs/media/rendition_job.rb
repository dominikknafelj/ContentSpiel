module Media
  # Makes the widths of one library image, once, on the `images` queue (one
  # thread, so a burst of uploads never starves the site's other jobs and
  # libvips never runs twice at once on a small machine).
  #
  # The settings are read when the job RUNS, never taken from its arguments: a
  # format saved between the enqueue and the run, or a regenerate that queued
  # an image twice, makes the image once, with the newest settings. A job that
  # finds the image already made under them does nothing.
  #
  # What it writes, in this order: the preview, size and alpha flag when the
  # row has none (a row from before previews); each width, smallest first,
  # through Active Storage's own variant (a variant record per width and a
  # download of the original for each, which on the Disk service is a local
  # copy); then ONE write of the generation to the row. A page never lists a
  # width before that write, so a job that dies half way leaves the image as
  # it was and the next run finishes it (a variant already made is found, not
  # made again). The generation before the one that was current is deleted
  # afterwards: two generations are kept so a page cached under the old one
  # still finds its files.
  #
  # The content version moves once per image, at the end, and only for an image a live page can show, because the library's
  # widths change the `srcset` a cached page holds. The variant records the
  # job makes do not bump (`config/initializers/public_site_version.rb`).
  #
  # A failure is retried twice and then recorded on the row by its class
  # (never its message, which can quote a path); a file libvips cannot read is
  # recorded at once, since a retry reads the same bytes. The image keeps its
  # preview either way.
  class RenditionJob < ApplicationJob
    queue_as :images

    retry_on StandardError, attempts: 3, wait: :polynomially_longer do |job, error|
      Media::RenditionJob.record_failure(job.arguments.first, error)
    end

    # Declared AFTER retry_on: Active Support takes the handler declared last
    # that matches, so before it the retry would also catch an image purged
    # before its job ran, and retry a row that is gone.
    discard_on ActiveJob::DeserializationError

    def self.record_failure(asset, error)
      return unless asset.is_a?(Media::Asset)

      asset.update_columns(renditions_failed_at: Time.current, renditions_error: error.class.name) # version: none (the failure is shown in CS Studio only; no page reads it)
    end

    def perform(asset)
      return if asset.trashed?

      span = OpenTelemetry::Trace.current_span
      latency = enqueued_at && ((Time.current - enqueued_at.to_time) * 1000).round
      span.set_attribute("image.queue_latency_ms", latency) if latency

      settings = ImageSettings.current
      fingerprint = settings.fingerprint
      decode(asset)
      return if asset.made_with?(fingerprint)

      files = make_widths(asset, settings, span)
      record(asset, fingerprint, files)
    rescue Media::Decoding::Unreadable, Media::Decoding::TooManyPixels => e
      self.class.record_failure(asset, e)
    end

    private

    # The preview, the size and the alpha flag, from one decode of the file,
    # for a row that has none of them.
    def decode(asset)
      return if asset.preview.present? && asset.width.present? && asset.height.present?

      result = asset.file.blob.open { |file| Media::Decoding.read(file, content_type: asset.content_type) }
      asset.update_columns(width: result.width, height: result.height, preview: result.preview, has_alpha: result.alpha) # version: none (a derived size and preview of a file whose generation does not exist yet; the end of the job bumps)
    end

    def make_widths(asset, settings, span)
      widths = Media::Renditions.widths_for(original_width: asset.width, configured: settings.widths)
      bytes_out = 0
      files = widths.map do |width|
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        transformations = Media::Renditions.transformations(
          width: width, format: settings.format, quality: settings.quality, content_type: asset.content_type
        )
        variant = asset.file.variant(transformations).processed
        span.set_attribute("image.width.#{width}.ms", ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round)
        bytes_out += variant.image.blob.byte_size
        { "width" => width, "key" => variant.variation.key, "digest" => variant.variation.digest }
      end
      span.set_attribute("image.bytes_in", asset.file.blob.byte_size)
      span.set_attribute("image.bytes_out", bytes_out)
      files
    end

    def record(asset, fingerprint, files)
      renditions = asset.renditions || {}
      old_current = renditions["current"]
      old_previous = renditions["previous"]
      current = { "fingerprint" => fingerprint, "files" => files }

      asset.update_columns( # version: bumped at the end of this method, once for the image
        renditions: { "current" => current, "previous" => old_current }.compact,
        renditions_fingerprint: fingerprint, renditions_failed_at: nil, renditions_error: nil
      )
      drop_generation(asset, old_previous, kept: [ current, old_current ])
      # A finished image moves the content version once, when a live page can
      # show it: the generation just written changes the srcset a cached page
      # holds. The write above is committed before this question, so a page
      # published meanwhile either sees the generation or bumps after it.
      PublicSite.bump_version! if asset.shown_publicly?
    end

    # The variant records of the generation before the one that was current,
    # unless a kept generation shares the file (the same variation).
    def drop_generation(asset, generation, kept:)
      digests = Array(generation && generation["files"]).map { |file| file["digest"] }
      digests -= kept.flat_map { |kept_generation| Array(kept_generation && kept_generation["files"]).map { |file| file["digest"] } }
      return if digests.empty?

      ActiveStorage::VariantRecord.where(blob_id: asset.file.blob.id, variation_digest: digests).find_each(&:destroy)
    end
  end
end
