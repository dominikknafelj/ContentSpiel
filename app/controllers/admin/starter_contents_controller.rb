module Admin
  # "Create starter pages" (design spec §6.1, Task 9), the setup wizard's
  # optional starter-content step available again from the Pages home --
  # `StarterContent.create_pages_and_posts!` reused as-is, in the site's
  # default language, exactly as the wizard's own step runs it.
  #
  # The Pages home only offers this while the starter sections are missing
  # (`StarterContent.added?`, the same check the wizard uses), but a stale
  # tab or a second click can still get here after they exist: the call is
  # idempotent anyway (it looks every page and post up first), so this just
  # says nothing needed doing instead of pretending it created something.
  #
  # Always a redirect to the Pages home, and the form posts with
  # `data-turbo-frame="_top"`: the new pages appear in the tree, which
  # lives in the layout's own column outside the `content` frame, so only
  # a full-page visit brings it up to date.
  #
  # Two tabs clicking at once (fix round 1, m3) are handled by
  # `StarterContent.add_once!` -- the same locked, re-checked path the setup
  # wizard takes (final fix wave, P23); a failure it raises becomes an alert
  # instead of a 500.
  class StarterContentsController < BaseController
    def create
      created = StarterContent.add_once!(locale: Locales.default)

      notice = created ? "Starter pages created" : "Starter pages already exist"
      redirect_to admin_root_path(**admin_url_options), status: :see_other, notice: notice
    rescue StarterContent::Error => error
      Rails.logger.warn("[starter pages] #{error.class}: #{error.message}")
      redirect_to admin_root_path(**admin_url_options), status: :see_other,
        alert: "Starter pages couldn't be created — a page may already use one of their addresses"
    end
  end
end
