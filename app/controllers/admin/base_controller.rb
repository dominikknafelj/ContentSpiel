module Admin
  # Everything in CS Studio (cs-studio spec §4.1): signed-in only (inherited
  # Authentication), the admin layout, the :admin channel for services, and the
  # editing locale every screen reads.
  class BaseController < ApplicationController
    layout "admin"
    before_action { Current.channel = :admin }
    helper_method :admin_locale, :admin_url_options, :root_page

    private

    # The homepage (final-fixes round, finding 12) -- one place for what
    # every Pages view and both of its controllers (`PagesController`'s own
    # tree replace/"no parent given" fallback, `TreeController`'s own tree
    # replace) otherwise each re-derived by hand as a bare `Page.find_by
    # (parent_id: nil)`, several times over, with nothing tying them
    # together as "the same lookup" beyond a shared literal -- `Page#
    # only_one_root_page` is what actually guarantees there's ever at most
    # one row this can match. A `helper_method` so every Pages view can call
    # it exactly like a controller action already can, the same way
    # `admin_locale`/`admin_url_options` already are.
    def root_page
      Page.find_by(parent_id: nil)
    end

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
