class SiteSetting < ApplicationRecord
  has_one_attached :logo

  validate :only_one_record_exists, on: :create
  validates :title, presence: true

  validate :locales_are_well_formed
  validate :default_locale_is_enabled

  after_commit :reset_cached_state

  def self.instance
    first || create!(title: "My Site")
  end

  def locale_codes
    Array(locales).map { |entry| entry["code"].to_s }
  end

  def locale_entry(code)
    Array(locales).find { |entry| entry["code"].to_s == code.to_s }
  end

  private

  def only_one_record_exists
    errors.add(:base, "only one SiteSetting may exist") if SiteSetting.exists?
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
