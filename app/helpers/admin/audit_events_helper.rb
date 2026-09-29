module Admin
  # View-side rendering for the audit log (design spec §5 "Audit log
  # module", Task 9): who an event was (`#audit_actor_label`) and where
  # its subject links to, if anywhere (`#audit_subject_path`).
  module AuditEventsHelper
    CHANNEL_LABELS = {
      "admin" => "Admin",
      "mcp" => "MCP",
      "setup" => "Setup",
      "console" => "Console",
      "system" => "System"
    }.freeze

    # Task 9 controller ruling: "the subject LINK for a post/page only
    # renders if the viewer can read that record (else plain label)".
    # `Audit::Event#subject` is the live record read back through its
    # polymorphic association (`optional: true` -- `Audit::Event`'s own
    # class comment: "an event outlives its actor and subject"), so a
    # deleted subject already reads back nil and falls straight through
    # to the caller's plain-label fallback with no separate check needed
    # here. `event.subject_type` picks which permission (and, for
    # User/Group/Settings, which admin area) to ask -- every other
    # subject type cataloged (a block, a tag, a token, a media asset) has
    # no admin page of its own to link to at all, so it always stays a
    # plain label.
    def audit_subject_path(event)
      return nil if event.subject.nil?

      case event.subject_type
      when "Post" then admin_post_path(event.subject_id, **admin_url_options) if can?("posts.read", event.subject)
      when "Page" then admin_page_path(event.subject_id, **admin_url_options) if can?("pages.read", event.subject)
      when "User" then edit_admin_user_path(event.subject_id, **admin_url_options) if can?("users.manage")
      when "AccessControl::Group" then edit_admin_group_path(event.subject_id, **admin_url_options) if can?("groups.manage")
      when "SiteSetting" then admin_settings_path(**admin_url_options) if can?("settings.manage")
      end
    end

    # "Who" (design spec §5: "time, who (user and token name), channel,
    # action"). `ApiToken` has no `name` column of its own (`Audit::
    # Snapshot.label_for`'s own fallback, "API token #id", is the same
    # call this makes) -- so an MCP write is labelled by its acting user's
    # email plus the token's id. `event.user_id` is the denormalised
    # acting user (design spec §4.1), read back through `event.user`; it
    # can be nil for a user later deleted, which still leaves the id on
    # the row as proof the event is provably theirs. A trusted code path
    # with no user at all (setup/console/system, `Audit.default_channel`)
    # is labelled by its channel instead.
    def audit_actor_label(event)
      return "#{event.user&.email_address || "a deleted user"} via API token ##{event.actor_id}" if event.actor_type == "ApiToken"
      return event.user&.email_address || "a deleted user" if event.user_id

      audit_channel_label(event.channel)
    end

    # The Channel column (fix round 1: rendered raw before this), and
    # `#audit_actor_label`'s own fallback -- one label per stored channel
    # string, so a reader never sees the bare column value (`"admin"`,
    # `"mcp"`) in two different casings depending on which part of the
    # page they're looking at.
    def audit_channel_label(channel)
      CHANNEL_LABELS.fetch(channel, channel.to_s.humanize)
    end
  end
end
