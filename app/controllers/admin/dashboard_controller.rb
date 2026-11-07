module Admin
  # CS Studio's start page. Open to every signed-in user: its module
  # (`StudioModules`' `:dashboard`) has `permission: nil`, so a user whose
  # groups hold no grants at all still lands here instead of a 403 the
  # moment they sign in. Each list it shows is read-scoped (`Dashboard::Feed`,
  # `Dashboard::WaitingForYou`, through `AccessControl.scope` and
  # `Notes.readable_threads`), so it simply comes back empty for them, the
  # same way every other admin list does, and its New post… and New page…
  # are drawn only for whoever may create one.
  class DashboardController < BaseController
    # Everything the page shows, each part read-scoped for the viewer
    # (`Dashboard::Feed`, `Activity`, `TranslationNeeds`) and loaded in a
    # constant number of queries.
    def show
      # Only a holder of settings.manage can fix mail, so only they are told
      # (the notice draws itself only while the last send failed).
      @mail_settings = MailSettings.current if can?("settings.manage")
      @feed = Dashboard::Feed.new(actor: Current.actor)
      @activity = Dashboard::Activity.new(actor: Current.actor)
      @translation_needs = Dashboard::TranslationNeeds.new(actor: Current.actor)
    end

    # Waiting for you, answered again by itself: what its filter's links and
    # a live note (`admin--notes--inbox`) fetch into
    # `turbo-frame#dashboard-waiting`. The partial alone, no layout, so the
    # answer pays nothing for the sidebar. Its address is the frame's and
    # never a page: any other request goes to the dashboard.
    def waiting
      return redirect_to(admin_root_path(**admin_url_options), status: :see_other) unless turbo_frame_request_id == Admin::DashboardScreen::WaitingPanelComponent::FRAME

      render partial: "admin/dashboard/waiting", locals: { waiting: Dashboard::WaitingForYou.new(actor: Current.actor, filter: params[:filter].to_s) }
    end
  end
end
