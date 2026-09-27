class Current < ActiveSupport::CurrentAttributes
  attribute :session, :site

  # Who is performing the current write, and through what door (spec §7.1) --
  # every `ApplicationService` reads these as its default `actor:` and hands
  # them to `authorize!`/`record_event` once those attachment points grow
  # teeth (sub-project 5). `actor` is a `User` (admin session), an `ApiToken`
  # (MCP) or nil (console, jobs, unauthenticated setup steps); `channel` is
  # one of `:admin | :mcp | :setup | :console | :system`, set by whichever
  # controller (or script) is driving the request -- `ApplicationController`
  # defaults to `:admin`, `McpController` overrides both to the authenticated
  # token and `:mcp`, `SetupController` overrides the channel to `:setup`.
  # Outside a request (console, rake tasks, seeds) both stay at their Ruby
  # default of nil, which callers should read as `:console`/`:system` rather
  # than crash on -- nothing in this sub-project requires an actor to be
  # present.
  attribute :actor, :channel
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
