# The page an invitation link opens (`/invitation#<token>`). The person has
# no account yet, so it is outside CS Studio and needs no sign-in. This is
# the MINIMAL version (plan Ruling P1): it answers the "expired" sentence
# only, so that the route the mail links to resolves; Task 9 replaces it
# with the accept page and its four answers. Never cached: the page is the
# answer to a credential.
class InvitationsController < ApplicationController
  layout "product"

  allow_unauthenticated_access
  before_action { response.cache_control.replace(no_store: true) }

  def show
  end
end
