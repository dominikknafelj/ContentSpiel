# Fills each locale's blank slug from that locale's title (spec §10.1), so an
# editor never has to type a URL segment. Reads the raw jsonb title hash rather
# than the Mobility reader, which would fall back to English and hand German a
# copy of the English slug. Never overwrites a slug that is already set --
# changing a published page's URL must stay a deliberate act.
module SlugGeneration
  extend ActiveSupport::Concern

  included do
    before_validation :fill_blank_slugs_from_titles
  end

  private

  def fill_blank_slugs_from_titles
    return unless generates_slugs?

    titles = read_attribute(:title).to_h
    ::Mobility.available_locales.each do |locale|
      accessor = ::Mobility.normalize_locale_accessor(:slug, locale)
      title = titles[locale.to_s]
      next if public_send(accessor).present? || title.blank?

      public_send("#{accessor}=", title.parameterize)
    end
  end

  def generates_slugs?
    true
  end
end
