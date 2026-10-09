class Current < ActiveSupport::CurrentAttributes
  attribute :session, :site

  # Who is performing the current write, and through what door (spec §7.1) --
  # every `ApplicationService` reads these as its default `actor:`, checks
  # it with `authorize!` and attributes its audit events to it
  # (access-control design spec §3.4/§4.2). `actor` is a `User` (admin
  # session), an `ApiToken` (MCP) or nil (console, jobs, unauthenticated
  # setup steps); `channel` is one of `:admin | :mcp | :setup | :console |
  # :system`, set by whichever controller (or script) is driving the
  # request -- `ApplicationController` defaults to `:admin`, `McpController`
  # overrides both to the authenticated token and `:mcp`, `SetupController`
  # overrides the channel to `:setup`. Outside a request (console, rake
  # tasks, seeds) both stay at their Ruby default of nil, which the checker
  # trusts like `:console`/`:system`; a nil actor on `:admin`/`:mcp` is
  # denied everything.
  attribute :actor, :channel

  # The request an audit event came from (access-control design spec §4.1),
  # copied onto every `Audit::Event` by `Audit.record`. Set by
  # `ApplicationController` and `McpController`; nil outside a request.
  attribute :request_id, :ip_address

  # `PublicSite.current_content_version`'s per-request memo.
  attribute :content_version

  # `AccessControl::ActorGrants`' per-request memo: a Hash keyed by actor
  # of the grants that actor acts under. Cleared after any grant or
  # membership commits (see ActorGrants).
  attribute :access_grants

  # The opaque id of the browser tab a notes request came from (the header
  # `X-Notes-Tab`, read by `Admin::NoteContainer`). `Notes::Signals` echoes
  # it in a record's signal so that tab can ignore its own echo; it is used
  # for nothing else and is nil outside a notes request.
  attribute :notes_tab
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
