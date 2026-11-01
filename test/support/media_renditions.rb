# Gives an asset a recorded generation without making any file: the keys and
# digests are the real variation ones, so the addresses are the real shape.
module MediaRenditions
  def make_renditions!(asset, widths: nil, fingerprint: nil)
    settings = ImageSettings.current
    widths ||= Media::Renditions.widths_for(original_width: asset.width, configured: settings.widths)
    files = widths.map do |width|
      variation = ActiveStorage::Variation.wrap(Media::Renditions.transformations(
        width: width, format: settings.format, quality: settings.quality, content_type: asset.content_type
      ))
      { "width" => width, "key" => variation.key, "digest" => variation.digest }
    end
    generation = { "fingerprint" => fingerprint || settings.fingerprint, "files" => files }
    asset.update_columns(renditions: { "current" => generation }, renditions_fingerprint: generation["fingerprint"]) # version: bumped on the next line
    PublicSite.bump_version! # a made generation changes the srcset a cached page holds
    asset.reload
  end
end
