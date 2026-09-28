module Admin
  # "Create starter pages" (design spec §6.1, Task 9), the setup wizard's
  # optional starter-content step available again from the Pages home --
  # `StarterContent.create_pages_and_posts!` reused as-is, in the site's
  # default language, exactly as the wizard and Avo's old action ran it.
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
  class StarterContentsController < BaseController
    def create
      if StarterContent.added?(locale: Locales.default)
        notice = "Starter pages already exist"
      else
        StarterContent.create_pages_and_posts!(locale: Locales.default)
        notice = "Starter pages created"
      end

      redirect_to admin_root_path(**admin_url_options), status: :see_other, notice: notice
    end
  end
end
