module Admin
  # "Create starter pages" (design spec §6.1, Task 9), the setup wizard's
  # optional starter-content step available again from the Pages module's
  # own index (`/pages`, dashboard spec Task 2 -- not CS Studio's home any
  # more, which is now the dashboard) -- `StarterContent
  # .create_pages_and_posts!` reused as-is, in the site's default language,
  # exactly as the wizard's own step runs it.
  #
  # The Pages index only offers this while the starter sections are missing
  # (`StarterContent.added?`, the same check the wizard uses), but a stale
  # tab or a second click can still get here after they exist: the call is
  # idempotent anyway (it looks every page and post up first), so this just
  # says nothing needed doing instead of pretending it created something.
  #
  # Always a redirect to the Pages index, and the form posts with
  # `data-turbo-frame="_top"`: the new pages appear in the tree, which
  # lives in the layout's own column outside the `content` frame, so only
  # a full-page visit brings it up to date.
  #
  # Two tabs clicking at once (fix round 1, m3) are handled by
  # `StarterContent.add_once!` -- the same locked, re-checked path the setup
  # wizard takes (final fix wave, P23) -- through `StarterContents::Add`,
  # which checks permissions first and turns a failure into an alert
  # instead of a 500.
  class StarterContentsController < BaseController
    def create
      result = StarterContents::Add.call

      if result.ok?
        notice = result.record ? "Starter pages created" : "Starter pages already exist"
        redirect_to pages_landing_path, status: :see_other, notice: notice
      else
        forbidden_or(result) { redirect_to pages_landing_path, status: :see_other, alert: result.errors.to_sentence }
      end
    end
  end
end
