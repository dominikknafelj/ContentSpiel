# The site's address for the length of a block. `SiteAddress.current` is
# memoised for the life of the process, so a test that sets `PUBLIC_HOST`
# itself leaves its address to every test that runs after it in the same
# worker. This is the one way a test sets it: `PUBLIC_HOST` is the value
# (nil for "not configured"), `SITEMAP_HOST` is cleared so the older name
# cannot answer instead, the memo is dropped on both sides, and both
# variables are put back as they were, also when the block raises.
#
# A test of `SITEMAP_HOST` itself sets it inside the block and calls
# `SiteAddress.reset!`; the `ensure` here still restores it.
module SiteAddressHelper
  VARIABLES = %w[PUBLIC_HOST SITEMAP_HOST].freeze

  def with_site_address(value)
    saved = ENV.to_h.slice(*VARIABLES)
    VARIABLES.each { |name| ENV.delete(name) }
    ENV["PUBLIC_HOST"] = value unless value.nil?
    SiteAddress.reset!
    yield
  ensure
    VARIABLES.each { |name| ENV.delete(name) }
    saved.each { |name, was| ENV[name] = was }
    SiteAddress.reset!
  end
end
