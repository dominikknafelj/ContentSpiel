# This controller has been generated to enable Rails' resource routes.
# More information on https://docs.avohq.io/4.0/controllers.html
class Avo::ApiTokensController < Avo::ResourcesController
  # See Avo::Resources::ApiToken for why creation is closed off here rather
  # than with a resource-level flag.
  before_action :refuse_manual_creation, only: [ :new, :create ]

  private
    def refuse_manual_creation
      redirect_to resources_api_tokens_path,
        flash: { warning: "API tokens are generated with ApiToken.generate!, not created by hand." }
    end
end
