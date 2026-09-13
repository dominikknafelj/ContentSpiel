# Ejected from the Avo gem so the admin panel is gated by this app's own
# Rails 8 session authentication rather than being left wide open.
# See https://docs.avohq.io/4.0/guides/rails-authentication-scaffold.html
module Avo
  class ApplicationController < BaseApplicationController
    include Authentication

    # Avo's controllers do not inherit from the app's ApplicationController, so
    # the sign-in route the Authentication concern redirects to has to be
    # delegated to the main app's route set.
    delegate :new_session_path, to: :main_app

    # Prepended so authentication runs before any of Avo's own before_actions.
    prepend_before_action :require_authentication
  end
end
