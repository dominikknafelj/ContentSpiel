module Admin
  # Everything in CS Studio (cs-studio spec §4.1): signed-in only (inherited
  # Authentication), the admin layout, the :admin channel for services, and the
  # editing locale every screen reads.
  class BaseController < ApplicationController
    layout "admin"
    before_action { Current.channel = :admin }
    helper_method :admin_locale, :admin_url_options

    private

    # The language being edited: ?locale= when it's enabled, else the site's
    # default. Invalid or disabled codes fall back silently (spec §8).
    def admin_locale
      @admin_locale ||= Locales.enabled?(params[:locale]) ? params[:locale].to_s : Locales.default
    end

    # Link params that keep the editing language across navigation.
    def admin_url_options
      admin_locale == Locales.default ? {} : { locale: admin_locale }
    end

    # Attachment point for roles/policies (sub-project 5). Permissive for now.
    def authorize!(_action, _record) = true
  end
end
