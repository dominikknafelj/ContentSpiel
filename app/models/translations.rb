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
  # `to_s`, whose `inspect` form isn't something to pin a format on --
  # and as *canonical* JSON, keys sorted at every level: Postgres jsonb
  # reorders keys on storage, so the in-memory value a save digests and the
  # reloaded one `translation_state` digests can differ in key order alone,
  # which must not read as an edit (review fix round 1, I1). A plain value
  # is digested with its line endings normalised to LF
  # (`normalize_newlines`): a browser re-submitting an unchanged
  # multi-line original sends CRLF where MCP or the console stored LF, and
  # that alone mustn't flag every translation of it as outdated.
  def digest(value)
    case value
    when RichText::Document then value.blank? ? nil : value.normalized.digest
    when Hash, Array then value.blank? ? nil : Digest::SHA256.hexdigest(canonical(value).to_json)
    else
      text = normalize_newlines(value.to_s).strip
      text.presence && Digest::SHA256.hexdigest(text)
    end
  end

  # What a translation's `translation_sources` entry keeps of an original so
  # a later change can be shown as a diff: a stripped, newline-normalised
  # String for plain text, one plain string per top-level block for rich
  # text, nil for anything else (a schema group's raw Hash/Array -- no
  # sensible text to show).
  def source_text(value)
    case value
    when RichText::Document then value.plain_paragraphs
    when Hash, Array, nil then nil
    else normalize_newlines(value.to_s).strip.presence
    end
  end

  # CRLF (and a lone CR) as LF -- the one spelling of a line break both
  # `digest` and `Tracker#translation_value_changed?` compare by.
  def normalize_newlines(text) = text.gsub(/\r\n?/, "\n")

  # `value` with every Hash's keys sorted (as Strings, so a Symbol-keyed
  # in-memory Hash and its String-keyed reload agree), recursively.
  def canonical(value)
    case value
    when Hash then value.to_h { |key, item| [ key.to_s, canonical(item) ] }.sort.to_h
    when Array then value.map { |item| canonical(item) }
    else value
    end
  end
end
