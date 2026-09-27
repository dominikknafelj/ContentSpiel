class Current < ActiveSupport::CurrentAttributes
  attribute :session, :site
  delegate :user, to: :session, allow_nil: true

  # The site's settings row, loaded at most once per request (spec §6.1) --
  # every public link, locale check and fallback read goes through it, and
  # `SiteSetting.instance` is a query per call. Outside a request (console,
  # jobs, MCP) the same memo applies until something resets it; SiteSetting
  # resets it after every committed change so a stale copy never outlives a
  # write in the same process.
  def site
    super || (self.site = SiteSetting.instance)
  end
end
