# This controller has been generated to enable Rails' resource routes.
# More information on https://docs.avohq.io/4.0/controllers.html
class Avo::UsersController < Avo::ResourcesController
  # See Avo::Resources::User for why deletion is closed off here rather than
  # with a resource-level flag.
  before_action :refuse_destroy, only: :destroy

  private
    def refuse_destroy
      redirect_to resources_users_path,
        flash: { warning: "Users can't be deleted from the admin -- it would lock everyone out." }
    end
end
