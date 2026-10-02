# Shared helpers for translation tracking (translation helpers spec §3): which
# language is the original, which ones are translations of it, and how an
# original's value is fingerprinted so a translation can remember which
# version of it it was saved against (`Translations::Tracker`).
module Translations
  module_function

  # Read at the time of use, never cached: the default language is editable
  # in CS Studio's Settings at runtime, and every state is relative to it.
  def primary_locale = Locales.default.to_s
  def target_locales = Locales.enabled.map(&:to_s) - [ primary_locale ]

  # A digest of an original value, or nil for a blank one. Rich text is
  # digested after `normalized`, so a change that only normalises (edge
  # whitespace, merged text nodes) isn't a change. A translated schema
  # *group* field's value is a raw jsonb Hash/Array (see
  # `Tracker#translation_value`), digested as JSON rather than through
  # `to_s`, whose `inspect` form isn't something to pin a format on.
  def digest(value)
    case value
    when RichText::Document then value.blank? ? nil : value.normalized.digest
    when Hash, Array then value.blank? ? nil : Digest::SHA256.hexdigest(value.to_json)
    else value.to_s.strip.presence && Digest::SHA256.hexdigest(value.to_s.strip)
    end
  end
end
