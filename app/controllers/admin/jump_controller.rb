module Admin
  # ⌘K's results (design pass spec §5.6). Open to every signed-in user, like
  # the dashboard: there's no permission to check for the endpoint itself,
  # because every row it returns is already narrowed to what this viewer
  # may read (`Jump::Search`). Read-only -- no service, no audit event.
  class JumpController < BaseController
    def show
      @query = params[:q].is_a?(String) ? params[:q] : ""
      @groups = Jump::Search.new(actor: Current.actor, query: @query, modules: admin_modules, url_options: admin_url_options).groups
      render layout: false
    end
  end
end
