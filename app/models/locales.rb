# The site's languages (spec §4): which are enabled, in what order, which is
# the default, and what each falls back to when a translation is missing.
# Everything reads `Current.site`, so a change in the settings takes effect on
# the next request without a deploy.
module Locales
  SUPPORTED = ::SUPPORTED_LOCALES

  module_function

  def enabled
    Current.site.locale_codes
  end

  def default
    Current.site.default_locale.to_s
  end

  def enabled?(code)
    code.present? && enabled.include?(code.to_s)
  end

  def name(code, native: false)
    entry = SUPPORTED[code.to_s]
    entry ? entry[native ? 1 : 0] : code.to_s.upcase
  end

  # The order translations are tried in for `code`: the language itself, the
  # fallbacks configured for it, the site's default language, then every other
  # enabled language in order -- so a page titled only in German still shows
  # *something* in Spanish rather than a blank heading.
  def fallback_chain(code)
    configured = Array(Current.site.locale_entry(code)&.fetch("fallbacks", nil)).map(&:to_s)
    ([ code.to_s ] + configured + [ default ] + enabled).uniq
  end

  # The one fallback-aware reader for public output (spec §4.3): the first
  # present value walking `fallback_chain(locale)`. Each step reads the
  # literal per-locale value -- plain Mobility readers no longer fall back on
  # their own (config/initializers/mobility.rb) -- so a translation left
  # blank in German shows the default language's text rather than nothing.
  #
  # Works for jsonb attributes and ActionText bodies alike: `present?` on a
  # rich text is "has non-blank content", and `Mobility.with_locale` reads
  # literally for both backends the same way, unlike passing `locale:` to the
  # accessor, which the action_text backend doesn't accept.
  def read(record, attribute, locale: I18n.locale)
    return nil if record.nil?

    fallback_chain(locale).each do |code|
      value = Mobility.with_locale(code) { record.public_send(attribute) }
      return value if value.present?
    end
    nil
  end
end
