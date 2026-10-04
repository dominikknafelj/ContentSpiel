module Admin
  module SiteNameHelper
    # The site's name in the default language -- the shell's wordmark subline
    # and the sign-in/reset screens' line above the heading. The default
    # language, never the editor's current one: these are the same whichever
    # language a screen is being edited in. One definition for views and
    # `Admin::AdminComponent`.
    def site_name = ::Locales.read(Current.site, :title, locale: ::Locales.default)
  end
end
