class SiteSetting < ApplicationRecord
  has_one_attached :logo

  validate :only_one_record_exists, on: :create

  # PagesController and config/sitemap.rb both use this value directly as a
  # locale to render/link pages in, with no fallback -- an admin typing
  # anything other than one of the site's configured locales would make every
  # page unreachable at the site's own root.
  validates :default_locale, inclusion: { in: -> { I18n.available_locales.map(&:to_s) } }

  def self.instance
    first || create!(title: "My Site")
  end

  private

  def only_one_record_exists
    errors.add(:base, "only one SiteSetting may exist") if SiteSetting.exists?
  end
end
