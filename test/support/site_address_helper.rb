# The site's address for the length of a block. `SiteAddress.current` is
# memoised for the life of the process, so a test that sets `PUBLIC_HOST`
# itself leaves its address to every test that runs after it in the same
# worker. This is the one way a test sets it: `PUBLIC_HOST` is the value
# (nil for "not configured"), the memo is dropped on both sides, and the
# variable is put back as it was, also when the block raises.
module SiteAddressHelper
  def with_site_address(value)
    with_variable("PUBLIC_HOST", value) { yield }
  end

  # The admin host for the length of a block, the same way; the public one is
  # left as it is, so it nests inside `with_site_address`.
  def with_admin_address(value)
    with_variable("ADMIN_HOST", value) { yield }
  end

  private
    def with_variable(name, value)
      saved = ENV.fetch(name, nil)
      ENV.delete(name)
      ENV[name] = value unless value.nil?
      SiteAddress.reset!
      yield
    ensure
      saved.nil? ? ENV.delete(name) : ENV[name] = saved
      SiteAddress.reset!
    end
end
