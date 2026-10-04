module Admin
  # The content header's language tabs (spec §6.2, handoff §10 A13; they
  # replaced the dotted language switcher): one entry per
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
  # marked with a hollow ring so an editor can tell, without opening every language,
  # which ones still need attention before publishing.
  #
  # `outdated:` is the set of codes whose translation was made against an
  # older version of the original (`Translations::Status.outdated_locales`,
  # translation helpers spec §4) -- a second, solid warn dot
  # with its own title and screen-reader text, since "something changed
  # since" asks for a different job than "something is still empty". Each
  # one carries a stable id (`.outdated_marker_id`) so "Mark as up to date"
  # can stream it away once the last outdated field in that language is
  # confirmed (`Admin::TranslationConfirmationsController`).
  class LanguageTabsComponent < AdminComponent
    def self.outdated_marker_id(code) = "language-switcher-outdated-#{code}"

    def initialize(current:, missing: [], outdated: [], url: ->(code) { "#" }, visible: 4)
      @visible = visible
      @current = current.to_s
      @missing = Array(missing).map(&:to_s)
      @outdated = Array(outdated).map(&:to_s)
      @url = url
    end

    def locales = Locales.enabled

    # The first `visible` languages, except that the current one always has
    # a tab: when it would fall into the overflow it takes the last visible
    # slot instead (handoff §10 A13).
    def tabs
      return locales if locales.size <= visible
      shown = locales.first(visible)
      shown[-1] = current unless shown.include?(current) || !locales.include?(current)
      shown
    end

    def overflow = locales - tabs

    def native_name(code) = Locales.name(code, native: true)

    def current?(code) = code.to_s == current

    def missing?(code) = missing.include?(code.to_s)

    def outdated?(code) = outdated.include?(code.to_s)

    def outdated_marker_id(code) = self.class.outdated_marker_id(code)

    def href(code) = url.call(code)

    private

    attr_reader :current, :missing, :outdated, :url, :visible
  end
end
