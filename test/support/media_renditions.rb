# Gives an asset a recorded generation. With no arguments the real job runs
# inline (the files are made, the generation is the real one); with `widths:`
# or `fingerprint:` a generation is written without making any file, its keys
# and digests the real variation ones so the addresses are the real shape (and,
# with no variant record behind them, answered 404 by the public routes).
module MediaRenditions
  def make_renditions!(asset, widths: nil, fingerprint: nil)
    return perform_rendition_job(asset) if widths.nil? && fingerprint.nil?

    settings = ImageSettings.current
    widths ||= Media::Renditions.widths_for(original_width: asset.width, configured: settings.widths)
    files = widths.map do |width|
      # Through the blob's own `variant`, as the job's are: the key and the
      # digest after Active Storage's default format, which a request decodes
      # to. Nothing is processed.
      variation = asset.file.blob.variant(Media::Renditions.transformations(
        width: width, format: settings.format, quality: settings.quality, content_type: asset.content_type
      )).variation
      { "width" => width, "key" => variation.key, "digest" => variation.digest }
    end
    generation = { "fingerprint" => fingerprint || settings.fingerprint, "files" => files }
    asset.update_columns(renditions: { "current" => generation }, renditions_fingerprint: generation["fingerprint"]) # version: bumped on the next line
    PublicSite.bump_version! # a made generation changes the srcset a cached page holds
    asset.reload
  end

  private

  def perform_rendition_job(asset)
    Media::RenditionJob.perform_now(asset.reload)
    asset.reload
  end
end
