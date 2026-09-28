class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Every admin request (CS Studio, setup, preview) writes through this actor and
  # channel by default (spec §7.1) -- `SetupController` overrides just the
  # channel to `:setup` since setup runs before an admin session may exist;
  # `McpController` doesn't inherit this at all (it's an `ActionController::API`,
  # see its own comment) and sets both itself from the bearer token.
  before_action :set_current_actor

  helper_method :current_user

  private
    def current_user
      Current.user
    end

    def set_current_actor
      Current.actor = Current.user
      Current.channel = :admin
      Current.request_id = request.request_id
      Current.ip_address = request.remote_ip
    end
end
