# The one lookup of the public site's own words (`public.` in
# `config/locales/public.en.yml`): the visitor's language where
# `public.<locale>.yml` has the key, English where it does not. No I18n
# fallbacks are configured and the test environment raises on a missing key,
# so a language without a file would otherwise show "Translation missing".
# `ThemeHelper#site_string`, `Blocks::CodeComponent#string` and
# `Blocks::NoteComponent#word` each decide WHICH keys they answer and read
# them here, so the rule is written once.
module PublicStrings
  # `locale:` is the language of a visitor's form (`Forms::PublicField`),
  # which is not always the request's; a language the application does not
  # know reads English, as one with no file does. `options` are I18n's own
  # (`count:` for a plural, an interpolation such as `label:`), handed on.
  def self.read(full_key, locale: I18n.locale, **options)
    locale = locale.to_s.to_sym
    I18n.t(full_key, **options, locale: I18n.available_locales.include?(locale) && I18n.exists?(full_key, locale) ? locale : :en)
  end
end
