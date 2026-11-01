module Media
  # Regenerate images (Settings → Images): queues the widths of every kept
  # image not made with the image settings now saved, or still missing its
  # preview or its size. Saving the card changes nothing by itself; this is
  # the press that does (owner's decision). Needs `settings.manage`.
  #
  # It looks at what is made, never at what is queued, so a second press
  # queues the same images again; `Media::RenditionJob` reads the settings
  # when it runs and does nothing for an image already made with them, so
  # each image is made once. It queues the plain job, not the backfill's:
  # a press made while an older job runs under the old settings must still
  # be made.
  #
  # Records `media.regenerated` on the site, with the count in its metadata,
  # and answers with the count as the result's record. Writes nothing to a
  # media row or to the public content version: the jobs do.
  class Regenerate < ApplicationService
    def initialize(actor: Current.actor)
      @actor = actor
    end

    def call
      site = Current.site || SiteSetting.instance
      return denied("settings.manage", site) unless authorize!("settings.manage", site)

      count = 0
      Media::Asset.needing_regeneration(ImageSettings.current(site).fingerprint).find_each do |asset|
        Media::RenditionJob.perform_later(asset)
        count += 1
      end
      record_event("media.regenerated", subject: site, metadata: { "count" => count })

      success(count)
    end
  end
end
