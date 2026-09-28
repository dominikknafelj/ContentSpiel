class SiteSetting < ApplicationRecord
  has_one_attached :logo

  validate :only_one_record_exists, on: :create
  validates :title, presence: true

  validate :locales_are_well_formed
  validate :social_links_are_safe, if: :will_save_change_to_social_links?
  validate :default_locale_is_enabled

  after_commit :reset_cached_state

  def self.instance
    first || create!(title: "My Site")
  end

  # The one rule for a social link's URL: an absolute http/https/mailto
  # URL. Enforced on save (`#social_links_are_safe`) and again by the
  # public footer (`ThemeHelper#safe_social_links`) as defence in depth for a
  # row written around validations.
  SOCIAL_LINK_SCHEMES = %w[http https mailto].freeze

  def self.safe_social_link?(url)
    scheme = URI.parse(url.to_s.strip).scheme
    scheme.present? && SOCIAL_LINK_SCHEMES.include?(scheme.downcase)
  rescue URI::InvalidURIError
    false
  end

  def locale_codes
    Array(locales).map { |entry| entry["code"].to_s }
  end

  def locale_entry(code)
    Array(locales).find { |entry| entry["code"].to_s == code.to_s }
  end

  # The row-by-row shape a name/URL fieldset naturally submits (any row can
  # be left blank) -- this is the one place that shape turns into the plain
  # `{ name => url }` hash `social_links` itself stores, so every caller
  # (the setup wizard's own site step, `Admin::SettingsController`) shares
  # the exact same "drop the empty rows" rule instead of each hand-keeping
  # its own copy (formerly `SetupController#site_params` alone).
  def social_link_rows=(rows)
    links = Array(rows).filter_map do |row|
      name, url = row[:name].to_s.strip, row[:url].to_s.strip
      [ name, url ] if name.present? && url.present?
    end
    self.social_links = links.to_h
  end

  private

  def only_one_record_exists
    errors.add(:base, "only one SiteSetting may exist") if SiteSetting.exists?
  end

  # Final fix wave (E): a link the footer can't render -- `github.com/dana`
  # typed without its scheme, most often -- is an error where it's typed,
  # rather than saving fine and then silently never appearing.
  def social_links_are_safe
    social_links.to_h.each do |name, url|
      errors.add(:social_links, "#{name} must start with https://, http:// or mailto:") unless self.class.safe_social_link?(url)
    end
  end

  def locales_are_well_formed
    codes = locale_codes
    return errors.add(:locales, "must enable at least one language") if codes.empty?

    unsupported = codes - ::SUPPORTED_LOCALES.keys
    errors.add(:locales, "contains an unsupported language: #{unsupported.join(', ')}") if unsupported.any?
    errors.add(:locales, "lists a language twice") if codes.uniq.size != codes.size

    Array(locales).each do |entry|
      missing = Array(entry["fallbacks"]).map(&:to_s) - codes
      errors.add(:locales, "#{entry['code']} falls back to a language that isn't enabled: #{missing.join(', ')}") if missing.any?
    end
  end

  # PagesController and config/sitemap.rb both use this value directly as a
  # locale to render/link pages in, with no fallback -- an admin typing
  # anything other than one of the site's enabled locales would make every
  # page unreachable at the site's own root.
  def default_locale_is_enabled
    errors.add(:default_locale, "must be one of the enabled languages") unless locale_codes.include?(default_locale.to_s)
  end

  # Both caches hold a copy of this row's state: Current.site the whole row,
  # Setup's latch whether setup is done. Resetting after commit (not after
  # save) so a rolled-back change never leaves them pointing at data that no
  # longer exists.
  def reset_cached_state
    Current.site = nil
    Setup.reset!
  end
end
