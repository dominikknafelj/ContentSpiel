# The `Authentication` concern, for Active Storage's own write endpoints
# (config/initializers/active_storage_access.rb, final fix wave C): the same
# session check CS Studio uses, but a signed-out request gets a bare 401
# instead of the concern's sign-in redirect -- these are API endpoints, not
# pages, and Active Storage's isolated controllers don't have the app's
# route helpers to redirect with anyway.
#
# `include Authentication` in the module body (not an `included` block), so
# `ActiveSupport::Concern` includes `Authentication` *first* and this
# module's `#request_authentication` sits above it in the lookup chain.
module ActiveStorageWriteAuthentication
  extend ActiveSupport::Concern
  include Authentication

  private

  def request_authentication = head(:unauthorized)
end
