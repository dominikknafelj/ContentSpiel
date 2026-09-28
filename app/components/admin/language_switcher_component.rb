module Admin
  # The content header's language switcher (spec §6.2): one entry per
  # `Locales.enabled`, named in its own language (`Locales.name(code,
  # native: true)`, same as `SetupHelper#language_name`) rather than in
  # whichever language the admin's own UI happens to be in -- a German
  # editor should still see "English", not "Englisch". `url:` is a lambda
  # rather than a route helper this component would have to know about,
  # since "switch language" means something different on every screen it
  # appears on (a page editor reloads the content frame; a post editor does
  # the same for a different resource) -- the caller already knows its own
  # `admin_locale`-aware URL and just hands over how to build it per code.
  #
  # `missing:` is the set of codes with an empty *required* translated field
  # (computed by the caller, likely from each field's `FieldSet#valid?`) --
  # marked with a dot so an editor can tell, without opening every language,
  # which ones still need attention before publishing.
  class LanguageSwitcherComponent < AdminComponent
    def initialize(current:, missing: [], url: ->(code) { "#" })
      @current = current.to_s
      @missing = Array(missing).map(&:to_s)
      @url = url
    end

    def locales = Locales.enabled

    def native_name(code) = Locales.name(code, native: true)

    def current?(code) = code.to_s == current

    def missing?(code) = missing.include?(code.to_s)

    def href(code) = url.call(code)

    private

    attr_reader :current, :missing, :url
  end
end
