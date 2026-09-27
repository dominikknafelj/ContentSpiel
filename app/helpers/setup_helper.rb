# Class strings shared by the setup wizard's views, kept in one place so the
# steps stay visually consistent. Product UI -- uses the Content·Spiel tokens.
module SetupHelper
  def setup_input_class
    "mt-1 block w-full rounded-cs border border-line-strong bg-surface px-3 py-2 text-ink focus:outline-2 focus:outline-accent"
  end

  def setup_label_class
    "block font-cs-mono text-label uppercase tracking-mono text-meta"
  end

  def setup_primary_button_class
    "inline-block cursor-pointer rounded-cs bg-accent px-4 py-2 font-semibold text-on-accent hover:bg-accent-hover"
  end

  def setup_secondary_link_class
    "inline-block cursor-pointer rounded-cs border border-line-strong px-4 py-2 text-ink hover:bg-sunken"
  end

  # Native name (e.g. "Deutsch" for "de") -- the setup wizard is naming
  # languages for whoever picks them, not describing them in English.
  def language_name(code)
    ::Locales.name(code, native: true)
  end

  # `<option>` pairs for every *supported* language (spec §4.1), not just the
  # ones currently enabled -- the languages step is exactly where a site
  # turns a new one on, so it has to offer the full ~40-language list rather
  # than the handful `Locales.enabled` already returns. Sorted by code, which
  # is already alphabetical in `SUPPORTED_LOCALES`.
  def language_options
    ::Locales::SUPPORTED.keys.map { |code| [ "#{language_name(code)} (#{code.upcase})", code ] }
  end
end
