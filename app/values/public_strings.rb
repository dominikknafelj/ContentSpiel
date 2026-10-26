# The one lookup of the public site's own words (`public.` in
# `config/locales/public.en.yml`): the visitor's language where
# `public.<locale>.yml` has the key, English where it does not. No I18n
# fallbacks are configured and the test environment raises on a missing key,
# so a language without a file would otherwise show "Translation missing".
# `ThemeHelper#site_string`, `Blocks::CodeComponent#string` and
# `Blocks::NoteComponent#word` each decide WHICH keys they answer and read
# them here, so the rule is written once.
module PublicStrings
  def self.read(full_key)
    I18n.t(full_key, locale: I18n.exists?(full_key, I18n.locale) ? I18n.locale : :en)
  end
end
